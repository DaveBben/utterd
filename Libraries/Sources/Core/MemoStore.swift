import Foundation

/// Errors thrown by ``MemoStore`` implementations.
public enum MemoStoreError: Error, Sendable {
    case recordNotFound(URL)
    case writeFailed(URL, underlying: Error)
}

/// Persistence interface for voice memo records.
/// All methods are `async` to support actor-based implementations.
public protocol MemoStore: Sendable {
    func insert(_ record: MemoRecord) async throws
    func contains(fileURL: URL) async -> Bool
    func oldestUnprocessed() async -> MemoRecord?
    func markProcessed(fileURL: URL, date: Date) async throws
}
