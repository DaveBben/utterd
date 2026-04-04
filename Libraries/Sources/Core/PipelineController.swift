import Foundation

/// Wires together the pipeline components: a `MemoConsumer` that ingests new voice
/// memo events into the store, and a `PipelineScheduler` that dispatches unprocessed
/// records through `TranscriptionPipelineStage` and optionally `NoteRoutingPipelineStage`.
@MainActor
public final class PipelineController {
    private let store: any MemoStore
    private let transcriptionService: any TranscriptionService
    private let watcherStream: AsyncStream<VoiceMemoEvent>
    private let logger: any WatcherLogger
    private let clock: any Clock<Duration>
    private let makeRoutingStage: ((@escaping @Sendable () async -> Void) -> NoteRoutingPipelineStage)?

    private var scheduler: PipelineScheduler?
    private var consumer: MemoConsumer?
    private var consumerTask: Task<Void, Never>?

    public init(
        store: any MemoStore,
        transcriptionService: any TranscriptionService,
        watcherStream: AsyncStream<VoiceMemoEvent>,
        logger: any WatcherLogger,
        clock: any Clock<Duration> = ContinuousClock(),
        makeRoutingStage: ((@escaping @Sendable () async -> Void) -> NoteRoutingPipelineStage)? = nil
    ) {
        self.store = store
        self.transcriptionService = transcriptionService
        self.watcherStream = watcherStream
        self.logger = logger
        self.clock = clock
        self.makeRoutingStage = makeRoutingStage
    }

    public func start() async {
        let stage = TranscriptionPipelineStage(
            transcriptionService: transcriptionService,
            store: store,
            logger: logger
        )

        let routingStage: NoteRoutingPipelineStage?
        if let factory = makeRoutingStage {
            routingStage = factory { [weak self] in
                await MainActor.run { self?.scheduler?.releaseLock() }
            }
        } else {
            routingStage = nil
        }

        let scheduler = PipelineScheduler(
            store: store,
            clock: clock,
            logger: logger,
            handler: { [store, logger] record in
                guard let result = await stage.process(record) else {
                    return false
                }
                if let routingStage {
                    // Routing stage marks processed and releases lock via onComplete
                    await routingStage.route(result)
                    return true
                } else {
                    // No routing stage — mark processed directly and return false
                    // to release the lock immediately
                    try? await store.markProcessed(fileURL: result.fileURL, date: Date())
                    logger.info("Transcript saved for \(result.fileURL.lastPathComponent) (no routing stage)")
                    return false
                }
            }
        )
        self.scheduler = scheduler

        let consumer = MemoConsumer(store: store, logger: logger)
        self.consumer = consumer

        let stream = watcherStream
        consumerTask = Task { [consumer] in
            await consumer.consume(stream)
        }

        await scheduler.start()
    }

    public func stop() {
        scheduler?.stop()
        consumerTask?.cancel()
        consumerTask = nil
    }
}
