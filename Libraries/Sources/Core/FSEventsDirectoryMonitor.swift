import CoreServices
import Foundation

// Thread safety: mutable state is protected by `queue`. The `start()` and
// `stop()` methods dispatch state mutations onto `queue` synchronously.
// The FSEvents callback also runs on `queue`. @unchecked Sendable is correct
// because all mutable access is serialized on a single dispatch queue.
public final class FSEventsDirectoryMonitor: DirectoryMonitor, @unchecked Sendable {

    private let directoryURL: URL
    private let queue: DispatchQueue

    private var eventStream: FSEventStreamRef?
    // fileprivate so the file-scope C callback can access it.
    // Must only be accessed from `queue`.
    fileprivate var continuation: AsyncStream<Set<URL>>.Continuation?
    private var isRunning = false

    // Retained-self pointer kept alive while FSEventStream is active.
    // Balanced by Unmanaged.release() in stopOnQueue().
    // Note: because passRetained prevents deallocation, deinit only fires
    // after stop() has been called. The deinit call to stop() is a safety
    // net for the case where start() was never called or already stopped.
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
            0.3,
            flags
        ) else {
            retained.release()
            cont.finish()
            throw DirectoryMonitorError.streamCreationFailed
        }

        // Commit state on the queue so the callback can safely access it.
        queue.sync {
            self.continuation = cont
            self.contextPointer = ptr
            self.eventStream = fsStream
            self.isRunning = true
        }

        FSEventStreamSetDispatchQueue(fsStream, queue)
        FSEventStreamStart(fsStream)

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

public enum DirectoryMonitorError: Error {
    case directoryNotFound(URL)
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
