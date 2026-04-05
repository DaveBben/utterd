import Foundation

/// Wires together the pipeline components: a `MemoConsumer` that ingests new voice
/// memo events into the store, and an immediate queue that dispatches unprocessed
/// records through `TranscriptionPipelineStage` and optionally `NoteRoutingPipelineStage`.
///
/// Processing is sequential and immediate — records are processed as soon as they
/// arrive, with no polling delay. Unprocessed records from previous sessions are
/// drained before new watcher events are handled.
@MainActor
public final class PipelineController {
    private let store: any MemoStore
    private let transcriptionService: any TranscriptionService
    private let watcherStream: AsyncStream<VoiceMemoEvent>
    private let logger: any WatcherLogger
    private let makeRoutingStage: (() -> NoteRoutingPipelineStage)?
    private let onItemProcessed: @Sendable () async -> Void

    private var processingTask: Task<Void, Never>?
    private var consumerTask: Task<Void, Never>?

    public init(
        store: any MemoStore,
        transcriptionService: any TranscriptionService,
        watcherStream: AsyncStream<VoiceMemoEvent>,
        logger: any WatcherLogger,
        makeRoutingStage: (() -> NoteRoutingPipelineStage)? = nil,
        onItemProcessed: @escaping @Sendable () async -> Void = {}
    ) {
        self.store = store
        self.transcriptionService = transcriptionService
        self.watcherStream = watcherStream
        self.logger = logger
        self.makeRoutingStage = makeRoutingStage
        self.onItemProcessed = onItemProcessed
    }

    public func start() async {
        // Cancel any prior run to prevent orphaned tasks processing concurrently
        stop()

        // 1. Create unbounded AsyncStream queue
        let (queue, queueContinuation) = AsyncStream<MemoRecord>.makeStream(
            bufferingPolicy: .unbounded
        )

        // 2. Drain: yield all pre-existing unprocessed records synchronously before
        //    spawning the consumer Task. This guarantees drain records enter the queue
        //    before any watcher events — no suspension points between drain and consumer start.
        let unprocessed = await store.allUnprocessed()
        for record in unprocessed {
            queueContinuation.yield(record)
        }

        // 3. Create MemoConsumer with onRecordInserted that yields to the queue
        let consumer = MemoConsumer(
            store: store,
            logger: logger,
            onRecordInserted: { record in
                queueContinuation.yield(record)
            }
        )

        // 4. Launch consumer Task — finishes the queue continuation when the watcher stream ends
        let stream = watcherStream
        consumerTask = Task { [consumer] in
            await consumer.consume(stream)
            queueContinuation.finish()
        }

        // 5. Launch processing Task: process records sequentially from the queue
        let transcriptionStage = TranscriptionPipelineStage(
            transcriptionService: transcriptionService,
            logger: logger
        )
        let routingStage = makeRoutingStage?()
        // Captured locally to avoid strong self-reference in Task closure
        let capturedStore = store
        let capturedOnItemProcessed = onItemProcessed

        processingTask = Task { [capturedStore, capturedOnItemProcessed] in
            for await record in queue {
                guard !Task.isCancelled else { break }
                await processOne(
                    record,
                    transcriptionStage: transcriptionStage,
                    routingStage: routingStage,
                    store: capturedStore,
                    onItemProcessed: capturedOnItemProcessed
                )
            }
        }
    }

    public func stop() {
        processingTask?.cancel()
        processingTask = nil
        consumerTask?.cancel()
        consumerTask = nil
    }

    // MARK: - Private

    private func processOne(
        _ record: MemoRecord,
        transcriptionStage: TranscriptionPipelineStage,
        routingStage: NoteRoutingPipelineStage?,
        store: any MemoStore,
        onItemProcessed: @Sendable () async -> Void
    ) async {
        guard let result = await transcriptionStage.process(record) else {
            if Task.isCancelled {
                // Cancellation is not failure — leave unprocessed for next startup
                return
            }
            try? await store.markFailed(
                fileURL: record.fileURL,
                reason: "Transcription failed",
                date: Date()
            )
            return
        }

        if let routingStage {
            let routingResult = await routingStage.route(result)
            switch routingResult {
            case .success:
                await onItemProcessed()
            case .failure(let reason):
                try? await store.markFailed(
                    fileURL: record.fileURL,
                    reason: reason,
                    date: Date()
                )
            case .cancelled:
                // Cancellation is not failure — leave unprocessed for next startup
                break
            }
        } else {
            try? await store.markProcessed(fileURL: record.fileURL, date: Date())
            await onItemProcessed()
        }
    }
}
