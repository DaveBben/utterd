import Foundation

/// Wires together the pipeline components: a `MemoConsumer` that ingests new voice
/// memo events into the store, and a `PipelineScheduler` that dispatches unprocessed
/// records through `TranscriptionPipelineStage`.
///
/// Stage 2 (LLM classification/routing) is not implemented here — `onResult` logs
/// receipt and the lock stays held until stage 2 releases it.
@MainActor
public final class PipelineController {
    private let store: any MemoStore
    private let transcriptionService: any TranscriptionService
    private let watcherStream: AsyncStream<VoiceMemoEvent>
    private let logger: any WatcherLogger
    private let clock: any Clock<Duration>

    private var scheduler: PipelineScheduler?
    private var consumer: MemoConsumer?
    private var consumerTask: Task<Void, Never>?

    public init(
        store: any MemoStore,
        transcriptionService: any TranscriptionService,
        watcherStream: AsyncStream<VoiceMemoEvent>,
        logger: any WatcherLogger,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.store = store
        self.transcriptionService = transcriptionService
        self.watcherStream = watcherStream
        self.logger = logger
        self.clock = clock
    }

    public func start() async {
        let stage = TranscriptionPipelineStage(
            transcriptionService: transcriptionService,
            store: store,
            logger: logger,
            onResult: { [logger] result in
                logger.info("Transcript emitted for \(result.fileURL.path), awaiting stage 2")
            }
        )

        let scheduler = PipelineScheduler(
            store: store,
            clock: clock,
            pollingInterval: .seconds(30),
            logger: logger,
            handler: { record in
                await stage.process(record)
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
