import Foundation

/// Bridges ``VoiceMemoWatcher`` events into persistent ``MemoStore`` records.
///
/// Receives an ``AsyncStream`` of ``VoiceMemoEvent``s and, for each new event,
/// creates a ``MemoRecord`` and writes it to the store. Duplicate URLs are
/// silently skipped; write failures are logged without interrupting the stream.
@MainActor
public final class MemoConsumer {
    private let store: any MemoStore
    private let logger: any WatcherLogger
    private let now: @Sendable () -> Date

    public init(
        store: any MemoStore,
        logger: any WatcherLogger,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.logger = logger
        self.now = now
    }

    /// Iterates the stream until it finishes, writing new memos to the store.
    public func consume(_ stream: AsyncStream<VoiceMemoEvent>) async {
        for await event in stream {
            guard await !store.contains(fileURL: event.fileURL) else { continue }

            let record = MemoRecord(
                fileURL: event.fileURL,
                dateCreated: now(),
                dateProcessed: nil
            )

            do {
                try await store.insert(record)
            } catch {
                logger.error("Failed to insert memo record for \(event.fileURL.lastPathComponent): \(error)")
            }
        }
    }
}
