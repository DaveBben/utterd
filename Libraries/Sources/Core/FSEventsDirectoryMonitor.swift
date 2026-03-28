import CoreServices
import Foundation

// Thread safety: all mutable state is accessed exclusively on the dedicated
// `queue` DispatchQueue, which serializes all FSEvents callbacks and lifecycle
// operations. @unchecked Sendable is correct here.
public final class FSEventsDirectoryMonitor: DirectoryMonitor, @unchecked Sendable {

    private let directoryURL: URL
    private let queue: DispatchQueue

    private var eventStream: FSEventStreamRef?
    // Internal so the file-scope C callback can access it.
    var continuation: AsyncStream<Set<URL>>.Continuation?
    private var isRunning = false

    // Retained-self pointer kept alive while FSEventStream is active.
    // Balanced by Unmanaged.release() in stop().
    private var contextPointer: UnsafeMutableRawPointer?

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.queue = DispatchQueue(label: "com.utterd.fsevents.\(UUID().uuidString)")
    }

    deinit {
        stop()
    }

    // MARK: - DirectoryMonitor

    public func start() throws -> AsyncStream<Set<URL>> {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            throw DirectoryMonitorError.directoryNotFound(directoryURL)
        }

        // Stop any existing stream before starting fresh.
        stop()

        let (stream, continuation) = AsyncStream<Set<URL>>.makeStream(
            bufferingPolicy: .bufferingOldest(16)
        )
        self.continuation = continuation

        let pathsToWatch = [directoryURL.path] as CFArray
        var context = FSEventStreamContext()
        // passRetained keeps self alive while the stream is active.
        let retained = Unmanaged.passRetained(self)
        contextPointer = retained.toOpaque()
        context.info = contextPointer

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagWatchRoot
        )

        guard let fsStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        ) else {
            retained.release()
            contextPointer = nil
            continuation.finish()
            throw DirectoryMonitorError.streamCreationFailed
        }

        eventStream = fsStream
        isRunning = true

        FSEventStreamSetDispatchQueue(fsStream, queue)
        FSEventStreamStart(fsStream)

        return stream
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        if let fsStream = eventStream {
            FSEventStreamStop(fsStream)
            FSEventStreamInvalidate(fsStream)
            FSEventStreamRelease(fsStream)
            eventStream = nil
        }

        continuation?.finish()
        continuation = nil

        if let ptr = contextPointer {
            Unmanaged<FSEventsDirectoryMonitor>.fromOpaque(ptr).release()
            contextPointer = nil
        }
    }
}

// MARK: - Error

public enum DirectoryMonitorError: Error {
    case directoryNotFound(URL)
    case streamCreationFailed
}

// MARK: - C callback

// Must be a free function (or a C function pointer compatible closure) because
// FSEventStreamCreate requires a C function pointer for its callback parameter.
private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let monitor = Unmanaged<FSEventsDirectoryMonitor>.fromOpaque(info).takeUnretainedValue()

    // kFSEventStreamCreateFlagWatchRoot: if the watched root is deleted or
    // unmounted, FSEvents fires kFSEventStreamEventFlagRootChanged. Signal
    // stream completion so the watcher layer can handle recovery.
    for i in 0..<numEvents {
        if eventFlags[i] & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
            monitor.continuation?.finish()
            return
        }
    }

    // kFSEventStreamCreateFlagUseCFTypes delivers paths as a CFArray of CFString.
    let paths = unsafeBitCast(eventPaths, to: CFArray.self) as NSArray
    var changedURLs = Set<URL>()
    for i in 0..<numEvents {
        if let path = paths[i] as? String {
            // Resolve symlinks so paths are canonical (e.g., /var → /private/var on macOS).
            // This ensures callers can compare against URLs constructed via FileManager APIs
            // without worrying about unexpanded symlink forms.
            changedURLs.insert(URL(fileURLWithPath: path).resolvingSymlinksInPath())
        }
    }

    if !changedURLs.isEmpty {
        monitor.continuation?.yield(changedURLs)
    }
}
