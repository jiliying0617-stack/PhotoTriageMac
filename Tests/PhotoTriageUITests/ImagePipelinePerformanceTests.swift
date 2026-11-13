import AppKit
import Foundation
import ImageIO
import Testing
@testable import PhotoTriageUI

struct ImagePipelinePerformanceTests {
    @Test func imageAndPreviewShareOneHardMemoryBudget() throws {
        let first = try pipelineImage(width: 64, height: 64)
        let cost = try pipelineCost(first)
        let cache = PhotoImageCache(totalCostLimit: cost * 2, countLimit: 10)
        let second = try pipelineImage(width: 64, height: 64)
        let third = try pipelineImage(width: 64, height: 64)
        cache.insert(first, for: "first", previewKey: "first-file")
        cache.insert(second, for: "second", previewKey: "second-file")
        #expect(cache.image(for: "first") === first)
        cache.insert(third, for: "third", previewKey: "third-file")

        #expect(cache.count == 2)
        #expect(cache.totalCost == cost * 2)
        #expect(cache.image(for: "second") == nil)
        #expect(cache.previewImage(for: "second-file") == nil)
        #expect(cache.previewImage(for: "first-file") === first)
    }

    @Test func previewFallsBackToRetainedLowerResolutionWithoutOwningEvictedFrame() throws {
        let cache = PhotoImageCache(totalCostLimit: 1024 * 1024, countLimit: 2)
        let small = try pipelineImage(width: 32, height: 32)
        let large = try pipelineImage(width: 64, height: 64)
        cache.insert(small, for: "small", previewKey: "file")
        cache.insert(large, for: "large", previewKey: "file")
        #expect(cache.previewImage(for: "file") === large)
        _ = cache.image(for: "small")
        cache.insert(try pipelineImage(width: 16, height: 16), for: "other", previewKey: "other-file")
        #expect(cache.image(for: "large") == nil)
        #expect(cache.previewImage(for: "file") === small)
        cache.clear()
        #expect(cache.count == 0)
        #expect(cache.totalCost == 0)
        #expect(cache.previewImage(for: "file") == nil)
    }

    @Test func oversizedOriginalIsNotRetainedOrResizedByCache() throws {
        let image = try pipelineImage(width: 2400, height: 1600)
        let cache = PhotoImageCache(totalCostLimit: 1024, countLimit: 20)
        cache.insert(image, for: "original", previewKey: "file")
        #expect(cache.image(for: "original") == nil)
        #expect(cache.previewImage(for: "file") == nil)
        #expect(cache.totalCost == 0)
        #expect(image.size == CGSize(width: 2400, height: 1600))
    }

    @Test func cacheEvictionReleasesImageInsteadOfKeepingPreviewOwner() throws {
        let cache = PhotoImageCache(totalCostLimit: 1024 * 1024, countLimit: 1)
        weak var released: NSImage?
        try autoreleasepool {
            let first = try pipelineImage(width: 64, height: 64)
            released = first
            cache.insert(first, for: "first", previewKey: "first-file")
        }
        #expect(released != nil)
        cache.insert(try pipelineImage(width: 64, height: 64), for: "second", previewKey: "second-file")
        #expect(released == nil)
        #expect(cache.previewImage(for: "first-file") == nil)
    }

    @Test func metadataCacheLookupDoesNotRequireTheFileToBeMounted() throws {
        let url = URL(fileURLWithPath: "/unmounted-PhotoTriage-test-\(UUID())/image.jpg")
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let version = "\(url.path)#\(date.timeIntervalSinceReferenceDate)#1234"
        let image = try pipelineImage(width: 64, height: 64)
        PhotoImageCache.shared.insert(image, for: "\(version)#64", previewKey: version)
        #expect(PhotoImagePipeline.cachedImage(for: url, maxPixelSize: 64,
            fileSizeBytes: 1234, modificationDate: date) === image)
        #expect(PhotoImagePipeline.cachedPreviewImage(for: url,
            fileSizeBytes: 1234, modificationDate: date) === image)
        // Missing metadata must take the asynchronous validation path instead of
        // silently treating an unverified previous file version as current.
        #expect(PhotoImagePipeline.cachedImage(for: url, maxPixelSize: 64,
            fileSizeBytes: 1234, modificationDate: nil) == nil)
        #expect(PhotoImagePipeline.cachedPreviewImage(for: url,
            fileSizeBytes: 1235, modificationDate: date) == nil)
    }

    @Test func concurrentCacheMutationsStayWithinBudget() async throws {
        let image = try pipelineImage(width: 32, height: 32)
        let cost = try pipelineCost(image)
        let cache = PhotoImageCache(totalCostLimit: cost * 8, countLimit: 8)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    cache.insert(image, for: "\(index)", previewKey: "\(index / 3)")
                    _ = cache.image(for: "\(index)")
                    _ = cache.previewImage(for: "\(index / 3)")
                }
            }
        }
        #expect(cache.count <= 8)
        #expect(cache.totalCost <= cost * 8)
    }

    @Test func decodeConcurrencyIsBoundedWithoutBlockingCooperativeTasks() async {
        let limiter = PhotoImageDecodeLimiter(maxConcurrentDecodes: 2)
        let state = PipelineConcurrencyCounter()
        let gate = DispatchSemaphore(value: 0)
        let started = PipelineAsyncSignal(target: 2)
        let tasks = (0..<8).map { index in
            Task {
                await limiter.run { shouldContinue -> Int? in
                    state.enter()
                    started.signal()
                    defer { state.leave() }
                    _ = gate.wait(timeout: .now() + 5)
                    return shouldContinue() ? index : nil
                }
            }
        }
        await started.wait()
        #expect(state.active == 2)
        // Unrelated Swift tasks can run while both synchronous decodes are busy.
        let heartbeat = await Task.detached { 42 }.value
        #expect(heartbeat == 42)
        for _ in 0..<tasks.count { gate.signal() }
        for task in tasks { _ = await task.value }
        #expect(state.maximum == 2)
        #expect(state.active == 0)
    }

    @Test func cancellationResumesCallerBeforeSynchronousDecodeFinishes() async {
        let limiter = PhotoImageDecodeLimiter(maxConcurrentDecodes: 1)
        let gate = DispatchSemaphore(value: 0)
        let started = PipelineAsyncSignal(target: 1)
        let finished = PipelineAsyncSignal(target: 1)
        let task = Task {
            await limiter.run { shouldContinue -> Int? in
                started.signal()
                _ = gate.wait(timeout: .now() + 5)
                defer { finished.signal() }
                return shouldContinue() ? 42 : nil
            }
        }
        await started.wait()
        task.cancel()
        let value = await task.value
        #expect(value == nil)
        // The result above must not wait for ImageIO to finish. The running
        // decode still occupies its slot until it really exits (no oversubscribe).
        #expect(!finished.hasReachedTarget)
        gate.signal()
        await finished.wait()
    }

    @Test func cancelledQueuedDecodeDoesNotRunItsWork() async {
        let limiter = PhotoImageDecodeLimiter(maxConcurrentDecodes: 1)
        let gate = DispatchSemaphore(value: 0)
        let started = PipelineAsyncSignal(target: 1)
        let secondStarted = PipelineAsyncSignal(target: 1)
        let first = Task {
            await limiter.run { _ -> Int? in
                started.signal()
                _ = gate.wait(timeout: .now() + 5)
                return 1
            }
        }
        await started.wait()
        let cancelled = Task {
            await limiter.run { _ -> Int? in
                secondStarted.signal()
                return 2
            }
        }
        cancelled.cancel()
        #expect(await cancelled.value == nil)
        gate.signal()
        #expect(await first.value == 1)
        let last = await limiter.run { _ -> Int? in 3 }
        #expect(last == 3)
        #expect(!secondStarted.hasReachedTarget)
    }
}

private func pipelineImage(width: Int, height: Int) throws -> NSImage {
    let context = try #require(CGContext(data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    return NSImage(cgImage: image, size: NSSize(width: width, height: height))
}

private func pipelineCost(_ image: NSImage) throws -> Int {
    let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    return cgImage.bytesPerRow * cgImage.height
}

private final class PipelineConcurrencyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var activeCount = 0
    private var maximumCount = 0
    var active: Int { lock.withLock { activeCount } }
    var maximum: Int { lock.withLock { maximumCount } }
    func enter() { lock.withLock { activeCount += 1; maximumCount = max(maximumCount, activeCount) } }
    func leave() { lock.withLock { activeCount -= 1 } }
}

private final class PipelineAsyncSignal: @unchecked Sendable {
    private let lock = NSLock()
    private let target: Int
    private var count = 0
    private var continuation: CheckedContinuation<Void, Never>?
    init(target: Int) { self.target = target }
    var hasReachedTarget: Bool { lock.withLock { count >= target } }
    func signal() {
        let ready: CheckedContinuation<Void, Never>? = lock.withLock {
            count += 1
            guard count >= target else { return nil }
            defer { continuation = nil }
            return continuation
        }
        ready?.resume()
    }
    func wait() async {
        await withCheckedContinuation { next in
            let ready = lock.withLock {
                if count >= target { return true }
                continuation = next
                return false
            }
            if ready { next.resume() }
        }
    }
}
