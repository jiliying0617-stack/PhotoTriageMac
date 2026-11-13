import Foundation
#if canImport(CoreServices)
import CoreServices
#endif

public protocol WorkspaceFileWatching: AnyObject, Sendable {
    func start()
    func stop()
    func takeChangedPaths() -> Set<String>?
}

public extension WorkspaceFileWatching {
    func takeChangedPaths() -> Set<String>? { nil }
}

#if canImport(CoreServices)
public final class WorkspaceFileWatcher: WorkspaceFileWatching, @unchecked Sendable {
    /// FSEvents retains this context, never the watcher itself. A queued callback
    /// after stop/deinit safely observes a nil weak target instead of raw self.
    private final class CallbackContext {
        weak var watcher: WorkspaceFileWatcher?
        init(_ watcher: WorkspaceFileWatcher) { self.watcher = watcher }
    }
    private let rootPaths: [String]
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "PhotoTriage.WorkspaceFileWatcher")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var stream: FSEventStreamRef?
    private let changesLock = NSLock()
    private var changedPaths: Set<String> = []
    private var needsFullScan = false

    public func takeChangedPaths() -> Set<String>? {
        changesLock.lock()
        defer { changesLock.unlock() }
        let result = needsFullScan ? nil : changedPaths
        changedPaths = []
        needsFullScan = false
        return result
    }

    public init(rootPaths: [String], onChange: @escaping @Sendable () -> Void) {
        self.rootPaths = rootPaths
        self.onChange = onChange
        queue.setSpecific(key: queueKey, value: true)
    }

    deinit {
        stop()
    }

    public func start() {
        performOnQueue { startOnQueue() }
    }

    private func performOnQueue(_ operation: () -> Void) {
        // A callback may release the final owner or stop the watcher itself.
        // Do not synchronously dispatch back onto the queue in that case.
        if DispatchQueue.getSpecific(key: queueKey) == true { operation() }
        else { queue.sync(execute: operation) }
    }

    private func startOnQueue() {
        guard stream == nil, !rootPaths.isEmpty else { return }

        let callbackContext = CallbackContext(self)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callbackContext).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<CallbackContext>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<CallbackContext>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )

        let latency: CFTimeInterval = 0.3
        let createdStream = withExtendedLifetime(callbackContext) { FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, pathsPointer, eventFlags, _ in
                guard let info else { return }
                guard let watcher = Unmanaged<CallbackContext>.fromOpaque(info).takeUnretainedValue().watcher else { return }
                let paths = unsafeBitCast(pathsPointer, to: NSArray.self) as? [String] ?? []
                watcher.changesLock.lock()
                watcher.changedPaths.formUnion(paths)
                for index in 0..<count {
                    let flags = eventFlags[index]
                    if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0 {
                        watcher.needsFullScan = true
                    }
                }
                watcher.changesLock.unlock()
                watcher.onChange()
            },
            &context,
            rootPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) }
        guard let stream = createdStream else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        if !FSEventStreamStart(stream) {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    public func stop() {
        performOnQueue { stopOnQueue() }
    }

    private func stopOnQueue() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
#else
public final class WorkspaceFileWatcher: WorkspaceFileWatching, @unchecked Sendable {
    public init(rootPaths: [String], onChange: @escaping @Sendable () -> Void) {}
    public func start() {}
    public func stop() {}
}
#endif
