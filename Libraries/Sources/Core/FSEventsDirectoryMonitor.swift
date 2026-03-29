import CoreServices
import Foundation

// Thread safety: mutable state is protected by `queue`. The `start()` and
// `stop()` methods dispatch state mutations onto `queue` synchronously.
// The FSEvents callback also runs on `queue`. @unchecked Sendable is correct
// because all mutable access is serialized on a single dispatch queue.
public final class FSEventsDirectoryMonitor: DirectoryMonitor, @unchecked Sendable {

    // FSEvents coalesces filesystem events within this window before delivery.
    // 0.3s balances responsiveness (well within the 5s detection target, SC-5)
    // with batching to avoid excessive callback invocations during burst iCloud syncs.
    private static let eventLatency: CFTimeInterval = 0.3

    private let directoryURL: URL
    private let queue: DispatchQueue

    private var eventStream: FSEventStreamRef?
    // fileprivate so the file-scope C callback can access it.
    // Must only be accessed from `queue`.
    fileprivate var continuation: AsyncStream<Set<URL>>.Continuation?
    private var isRunning = false

    // Retained-self pointer kept alive while FSEventStream is active.
    // Balanced by Unmanaged.release() in stopOnQueue().
    // IMPORTANT: callers MUST call stop() before dropping all references.
    // passRetained prevents deallocation while the stream is active, so
    // deinit only fires after stop() has already been called (making the
    // deinit call to stopOnQueue() a no-op safety net).
    private var contextPointer: UnsafeMutableRawPointer?

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.queue = DispatchQueue(label: "com.utterd.fsevents.\(UUID().uuidString)")
    }

    deinit {
        // Safety net — stopOnQueue() is a no-op if stop() was already called
        // (which it must have been for deinit to fire, since passRetained
        // prevents deallocation while the stream is active).
        stopOnQueue()
    }

    // MARK: - DirectoryMonitor

    public func start() throws -> AsyncStream<Set<URL>> {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            throw DirectoryMonitorError.directoryNotFound(directoryURL)
        }

        // Stop any existing stream before starting fresh.
        stop()

        let (stream, cont) = AsyncStream<Set<URL>>.makeStream(
            bufferingPolicy: .bufferingOldest(16)
        )

        let pathsToWatch = [directoryURL.path] as CFArray
        var context = FSEventStreamContext()
        // passRetained keeps self alive while the stream is active.
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

        // Commit state and activate the stream atomically on the queue.
        // Both must happen inside the same queue.sync to prevent a concurrent
        // stop() from releasing the stream between state commit and activation.
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
