import Foundation

final class PhotoImageDecodeLimiter: @unchecked Sendable {
    static let shared = PhotoImageDecodeLimiter()

    private let queue: OperationQueue

    init(maxConcurrentDecodes: Int = 2) {
        queue = OperationQueue()
        queue.name = "PhotoTriage.ImageDecode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = max(1, maxConcurrentDecodes)
    }

    // ImageIO is synchronous work. Dispatch it on a bounded operation queue rather
    // than blocking Swift's cooperative executor with semaphore.wait(). A scrolled
    // away cell can cancel while queued without ever decoding its large original.
    func run<T: Sendable>(
        _ work: @escaping @Sendable (@Sendable () -> Bool) -> T?
    ) async -> T? {
        let state = DecodeRequest<T>()
        let operation = BlockOperation {
            guard state.shouldContinue else { return }
            let value = autoreleasepool { work { state.shouldContinue } }
            state.finish(value)
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard state.install(continuation) else { return }
                queue.addOperation(operation)
            }
        } onCancel: {
            state.cancel()
            operation.cancel()
        }
    }
}

private final class DecodeRequest<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    private var isCancelled = false

    var shouldContinue: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isCancelled
    }

    func install(_ continuation: CheckedContinuation<Value?, Never>) -> Bool {
        lock.lock()
        if isCancelled {
            lock.unlock()
            continuation.resume(returning: nil)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func finish(_ value: Value?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let result = isCancelled ? nil : value
        lock.unlock()
        continuation?.resume(returning: result)
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: nil)
    }
}
