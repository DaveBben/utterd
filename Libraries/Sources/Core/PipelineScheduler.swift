import Foundation

/// Polls ``MemoStore`` on a fixed interval and dispatches the oldest unprocessed
/// record to a pipeline handler. Uses a lock to prevent concurrent processing.
@MainActor
public final class PipelineScheduler {
    private let store: any MemoStore
    private let clock: any Clock<Duration>
    private let pollingInterval: Duration
    private let handlerTimeout: Duration
    private let logger: any WatcherLogger
    private let handler: @Sendable (MemoRecord) async -> Bool

    private var isLocked: Bool = false
    private var schedulerTask: Task<Void, Never>?

    public init(
        store: any MemoStore,
        clock: any Clock<Duration> = ContinuousClock(),
        pollingInterval: Duration = .seconds(30),
        handlerTimeout: Duration = .seconds(300),
        logger: any WatcherLogger,
        handler: @escaping @Sendable (MemoRecord) async -> Bool
    ) {
        self.store = store
        self.clock = clock
        self.pollingInterval = pollingInterval
        self.handlerTimeout = handlerTimeout
        self.logger = logger
        self.handler = handler
    }

    /// Begins the scheduling loop. Resets the lock to `false` on every call
    /// so a crash mid-processing doesn't permanently block the queue.
    public func start() async {
        schedulerTask?.cancel()
        schedulerTask = nil

        isLocked = false
        logger.info("Scheduler started")

        schedulerTask = Task { [weak self] in
            guard let self else { return }
            await runLoop()
        }

        await Task.yield()
    }

    /// Cancels the scheduling loop.
    public func stop() {
        schedulerTask?.cancel()
        schedulerTask = nil
        logger.info("Scheduler stopped")
    }

    /// Releases the processing lock. Call this when the handler has permanently
    /// failed so the next polling cycle can attempt a new record.
    public func releaseLock() {
        isLocked = false
    }

    // MARK: - Private

    private func runLoop() async {
        while !Task.isCancelled {
            try? await clock.sleep(for: pollingInterval)
            guard !Task.isCancelled else { return }

            if isLocked {
                logger.info("Lock held, skipping")
                continue
            }

            guard let record = await store.oldestUnprocessed() else {
                continue
            }

            isLocked = true
            logger.info("Processing: \(record.fileURL.path)")

            let result = await withTaskGroup(of: Bool?.self, returning: Bool?.self) { group in
                group.addTask { await self.handler(record) }
                group.addTask {
                    try? await self.clock.sleep(for: self.handlerTimeout)
                    return nil
                }
                let first = await group.next()!
                group.cancelAll()
                return first
            }

            if result == nil {
                logger.error("Handler timed out for \(record.fileURL.path), releasing lock")
                releaseLock()
            } else if result == false {
                releaseLock()
            }
        }
    }
}
