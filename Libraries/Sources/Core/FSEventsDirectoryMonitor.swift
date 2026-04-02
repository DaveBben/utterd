import CoreServices
import Foundation

// @unchecked Sendable: all mutable state is serialized on `queue`.
public final class FSEventsDirectoryMonitor: DirectoryMonitor, @unchecked Sendable {

    private static let eventLatency: CFTimeInterval = 0.3

    private let directoryURL: URL
    private let queue: DispatchQueue

    private var eventStream: FSEventStreamRef?
    // fileprivate: accessed by the C callback. Must only be read/written from `queue`.
    fileprivate var continuation: AsyncStream<Set<URL>>.Continuation?
    private var isRunning = false

    // passRetained prevents dealloc while the stream is active.
    // Callers MUST call stop() before dropping all references.
    private var contextPointer: UnsafeMutableRawPointer?

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.queue = DispatchQueue(label: "com.utterd.fsevents.\(UUID().uuidString)")
    }

    deinit {
        stopOnQueue()
    }

    // MARK: - DirectoryMonitor

    public func start() throws -> AsyncStream<Set<URL>> {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            throw DirectoryMonitorError.directoryNotFound(directoryURL)
        }

        stop()

        let (stream, cont) = AsyncStream<Set<URL>>.makeStream(
            bufferingPolicy: .bufferingOldest(16)
        )

        let pathsToWatch = [directoryURL.path] as CFArray
        var context = FSEventStreamContext()
        let retained = Unmanaged.passRetained(self)
        let ptr = retained.toOpaque()
        context.info = ptr

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
            Self.eventLatency,
            flags
        ) else {
            retained.release()
            cont.finish()
            throw DirectoryMonitorError.streamCreationFailed
        }

        // Atomic on queue to prevent concurrent stop() from interleaving.
        queue.sync {
            self.continuation = cont
            self.contextPointer = ptr
            self.eventStream = fsStream
            self.isRunning = true
            FSEventStreamSetDispatchQueue(fsStream, queue)
            FSEventStreamStart(fsStream)
        }

        return stream
    }

    public func stop() {
        queue.sync { stopOnQueue() }
    }

    // Must be called on `queue` (or from `deinit` where no races are possible).
    private func stopOnQueue() {
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

/// Errors thrown by ``FSEventsDirectoryMonitor/start()``.
public enum DirectoryMonitorError: Error {
    /// The monitored directory does not exist at the given URL.
    case directoryNotFound(URL)
    /// `FSEventStreamCreate` returned nil — typically indicates a system resource
    /// issue (e.g., too many open event streams). This is rare and generally not
    /// recoverable without releasing other streams first.
    case streamCreationFailed
}

// MARK: - C callback

// Must be a free function because FSEventStreamCreate requires a C function pointer.
// Runs on the monitor's `queue` (set via FSEventStreamSetDispatchQueue).
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
    // This unsafeBitCast is correct only when that flag is set (see flags above).
    let paths = unsafeBitCast(eventPaths, to: CFArray.self) as NSArray
    var changedURLs = Set<URL>()
    for i in 0..<numEvents {
        if let path = paths[i] as? String {
            changedURLs.insert(URL(fileURLWithPath: path).resolvingSymlinksInPath())
        }
    }

    if !changedURLs.isEmpty {
        monitor.continuation?.yield(changedURLs)
    }
}
