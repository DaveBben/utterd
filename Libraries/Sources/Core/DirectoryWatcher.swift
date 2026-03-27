import CoreServices
import Foundation

/// Errors that can occur when setting up or running the directory watcher.
public enum DirectoryWatcherError: Error, Sendable {
    /// The specified directory does not exist.
    case directoryNotFound(URL)
    /// The specified path exists but is not a directory.
    case notADirectory(URL)
    /// Insufficient permissions to read the directory.
    case permissionDenied(URL)
    /// The watched directory was deleted while the watcher was running.
    case directoryDeleted(URL)
}

/// Monitors a directory for new `.m4a` files and emits their URLs via an async stream.
///
/// The watcher begins monitoring when created and stops when the `events` stream
/// is cancelled (by the consuming task being cancelled) or when the watched directory
/// is deleted.
///
/// Only files that appear *after* the watcher starts are emitted. Pre-existing files
/// are ignored. Each file path is emitted at most once per watcher session.
public struct DirectoryWatcher: Sendable {
    /// An async stream of URLs for new `.m4a` files detected in the watched directory.
    public let events: AsyncStream<URL>

    /// Creates a watcher that monitors `directory` for new `.m4a` files.
    ///
    /// - Parameter directory: The directory to watch. Must exist and be readable.
    /// - Throws: `DirectoryWatcherError` if the directory is invalid or inaccessible.
    public init(directory: URL) throws {
        let path = directory.path

        // Validate: exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw DirectoryWatcherError.directoryNotFound(directory)
        }

        // Validate: is a directory
        guard isDirectory.boolValue else {
            throw DirectoryWatcherError.notADirectory(directory)
        }

        // Validate: readable
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw DirectoryWatcherError.permissionDenied(directory)
        }

        // Snapshot existing .m4a file names so we can ignore them
        let existingNames = Self.snapshotM4ANames(in: directory)

        events = AsyncStream<URL> { continuation in
            // WatcherContext holds all mutable state and runs on the FSEvents dispatch queue.
            // Using @unchecked Sendable because access is serialized via the DispatchQueue.
            final class WatcherContext: @unchecked Sendable {
                var seenNames: Set<String>
                let continuation: AsyncStream<URL>.Continuation
                let directory: URL

                init(
                    seenNames: Set<String>,
                    continuation: AsyncStream<URL>.Continuation,
                    directory: URL
                ) {
                    self.seenNames = seenNames
                    self.continuation = continuation
                    self.directory = directory
                }

                func handleEvent() {
                    guard
                        let contents = try? FileManager.default.contentsOfDirectory(
                            at: directory,
                            includingPropertiesForKeys: nil,
                            options: .skipsHiddenFiles
                        )
                    else {
                        // Directory scan failed (e.g., directory was deleted)
                        continuation.finish()
                        return
                    }

                    for fileURL in contents
                    where fileURL.pathExtension.lowercased() == "m4a" {
                        let name = fileURL.lastPathComponent
                        if !seenNames.contains(name) {
                            seenNames.insert(name)
                            continuation.yield(fileURL)
                        }
                    }
                }
            }

            let context = WatcherContext(
                seenNames: existingNames,
                continuation: continuation,
                directory: directory
            )

            // Retain the context as an unmanaged raw pointer for FSEvents callback info
            let contextPtr = Unmanaged.passRetained(context).toOpaque()

            var fsContext = FSEventStreamContext(
                version: 0,
                info: contextPtr,
                retain: { ptr in ptr },
                release: { ptr in
                    guard let ptr else { return }
                    Unmanaged<WatcherContext>.fromOpaque(ptr).release()
                },
                copyDescription: nil
            )

            // FSEvents C callback: recover context and handle the event
            let fsCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
                guard let info else { return }
                let ctx = Unmanaged<WatcherContext>.fromOpaque(info).takeUnretainedValue()
                ctx.handleEvent()
            }

            let pathsToWatch = [path] as CFArray
            guard
                let stream = FSEventStreamCreate(
                    nil,
                    fsCallback,
                    &fsContext,
                    pathsToWatch,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                    0.3,  // latency in seconds — coalesces rapid events
                    FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
                )
            else {
                continuation.finish()
                return
            }

            // Wrap the FSEventStreamRef (OpaquePointer) so it's capturable in @Sendable closures
            final class StreamBox: @unchecked Sendable {
                let ref: FSEventStreamRef
                init(_ ref: FSEventStreamRef) { self.ref = ref }
            }
            let streamBox = StreamBox(stream)

            let queue = DispatchQueue(label: "com.utterd.directorywatcher", qos: .utility)
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)

            continuation.onTermination = { _ in
                FSEventStreamStop(streamBox.ref)
                FSEventStreamInvalidate(streamBox.ref)
                FSEventStreamRelease(streamBox.ref)
            }
        }
    }

    // MARK: - Private Helpers

    /// Returns the set of `.m4a` file names currently in `directory`.
    private static func snapshotM4ANames(in directory: URL) -> Set<String> {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        else {
            return []
        }
        let names = contents
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .map { $0.lastPathComponent }
        return Set(names)
    }
}
