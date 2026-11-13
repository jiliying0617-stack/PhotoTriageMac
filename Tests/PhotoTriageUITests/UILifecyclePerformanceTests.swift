import AppKit
import PhotoTriageCore
import SwiftUI
import Testing
@testable import PhotoTriageUI

@MainActor
struct UILifecyclePerformanceTests {
    @Test func isolatedScrollIndicatorPreservesProgressClamping() {
        let metrics = AssetListScrollMetrics()
        #expect(metrics.progress == 0)
        metrics.viewportHeight = 100
        metrics.contentHeight = 1000
        metrics.scrollOffset = 450
        #expect(metrics.progress == 0.5)
        metrics.scrollOffset = 2000
        #expect(metrics.progress == 1)
        metrics.scrollOffset = -50
        #expect(metrics.progress == 0)
    }

    @Test func offscreenThumbnailStateReleasesItsImage() async {
        let state = ThumbnailImageState()
        weak var retainedImage: NSImage?
        await state.load(request()) { _, _, _ in
            let image = NSImage(size: NSSize(width: 520, height: 520))
            retainedImage = image
            return image
        }
        #expect(retainedImage != nil)
        state.releaseImage()
        #expect(state.image == nil)
        #expect(retainedImage == nil)
    }

    @Test func completedOffscreenWorkCannotRestoreAnImageAfterRelease() async throws {
        let state = ThumbnailImageState()
        var completion: CheckedContinuation<NSImage?, Never>?
        let request = request()
        let work = Task { @MainActor in
            await state.load(request) { _, _, _ in
                await withCheckedContinuation { completion = $0 }
            }
        }
        for _ in 0..<100 where completion == nil { await Task.yield() }
        let finishLoad = try #require(completion)
        state.releaseImage()
        finishLoad.resume(returning: NSImage(size: NSSize(width: 520, height: 520)))
        await work.value
        #expect(state.image == nil)
    }

    @Test func recycledThumbnailDoesNotForceAnUnnecessaryCacheRefresh() async {
        let state = ThumbnailImageState()
        let first = request()
        var policies: [PhotoImageCachePolicy] = []
        let loader: ThumbnailImageState.Loader = { _, _, policy in
            policies.append(policy)
            return NSImage(size: NSSize(width: 10, height: 10))
        }
        await state.load(first, loader: loader)
        let other = request()
        await state.load(other, loader: loader)
        let refreshed = ThumbnailLoadRequest(assetID: other.assetID, fileURL: other.fileURL,
            fileSizeBytes: other.fileSizeBytes, modificationDate: other.modificationDate,
            maxPixelSize: other.maxPixelSize, refreshToken: UUID())
        await state.load(refreshed, loader: loader)
        #expect(policies.count == 3)
        #expect(policies[0] == .readWrite)
        #expect(policies[1] == .readWrite)
        #expect(policies[2] == .refresh)
    }

    @Test func thumbnailRequestIncludesFileModificationDate() {
        let first = request()
        let changed = ThumbnailLoadRequest(assetID: first.assetID, fileURL: first.fileURL,
            fileSizeBytes: first.fileSizeBytes, modificationDate: Date(timeIntervalSince1970: 10),
            maxPixelSize: first.maxPixelSize, refreshToken: first.refreshToken)
        #expect(first != changed)
    }

    @Test func unchangedComparisonUpdatesDoNotDecodeOrRedrawFullResolutionImages() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: true)
        var loads = 0
        let renderer = InvalidationRecordingImageView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let host = CompareAssetImageHostView(
            frame: NSRect(x: 0, y: 0, width: 300, height: 200), imageRenderer: renderer
        ) { _, _, _ in
            loads += 1
            return NSImage(size: NSSize(width: 6000, height: 4000))
        }
        window.contentView = host
        defer { window.contentView = nil }
        var asset = fixtureAsset()
        let refreshToken = UUID()
        let url = URL(fileURLWithPath: "/nonexistent-test-fixture/\(UUID()).png")
        func configure() {
            host.configure(asset: asset, fileURL: url, refreshToken: refreshToken,
                maxPixelSize: 6000, contentMode: .fit, locksToBounds: false, showsLoadingIndicator: false)
        }
        configure()
        for _ in 0..<100 where host.displayedImage == nil { await Task.yield() }
        #expect(host.displayedImage != nil)
        host.layoutSubtreeIfNeeded()
        #expect(renderer.invalidationRequests > 0)
        renderer.invalidationRequests = 0
        // Ratings and P-tag updates change the cell model, not image pixels.
        for index in 0..<100 {
            asset.ratingState = index.isMultiple(of: 2) ? .keep : .reject
            configure()
        }
        #expect(loads == 1)
        #expect(renderer.invalidationRequests == 0)
        #expect(host.displayedImage?.size == NSSize(width: 6000, height: 4000))
    }

    @Test func actualImageDrawingChangesStillInvalidateTheRenderer() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: true)
        let renderer = InvalidationRecordingImageView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.contentView = renderer
        defer { window.contentView = nil }
        renderer.invalidationRequests = 0
        renderer.rotationDegrees = 90
        #expect(renderer.invalidationRequests == 1)
        #expect(renderer.needsDisplay)
        renderer.invalidationRequests = 0
        renderer.rotationDegrees = 90
        #expect(renderer.invalidationRequests == 0)
        renderer.contentMode = .fill
        #expect(renderer.invalidationRequests == 1)
        #expect(renderer.needsDisplay)
        renderer.invalidationRequests = 0
        renderer.locksToBounds = true
        #expect(renderer.invalidationRequests == 1)
        #expect(renderer.needsDisplay)
        renderer.invalidationRequests = 0
        let image = NSImage(size: NSSize(width: 10, height: 10))
        renderer.image = image
        #expect(renderer.invalidationRequests == 1)
        #expect(renderer.needsDisplay)
        renderer.invalidationRequests = 0
        renderer.image = image
        #expect(renderer.invalidationRequests == 0)
    }

    @Test func zoomEventsAreLimitedToTheVisibleOwningWindow() {
        _ = NSApplication.shared
        let owner = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled], backing: .buffered, defer: true)
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled], backing: .buffered, defer: true)
        let monitor = ScrollWheelZoomView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        owner.contentView?.addSubview(monitor)
        defer { monitor.removeFromSuperview() }
        #expect(monitor.shouldHandleScroll(in: owner))
        #expect(!monitor.shouldHandleScroll(in: other))
        #expect(!monitor.shouldHandleScroll(in: nil))
        monitor.isHidden = true
        #expect(!monitor.shouldHandleScroll(in: owner))
    }

    @Test func thumbnailCardsOnlyInvalidateWhenTheirDisplayedInputsChange() {
        let asset = fixtureAsset()
        let token = UUID()
        let card = AssetCompareThumbnailCard(asset: asset, fileURL: nil, refreshToken: token, isSelected: false, isViewed: false)
        let same = AssetCompareThumbnailCard(asset: asset, fileURL: nil, refreshToken: token, isSelected: false, isViewed: false)
        let selected = AssetCompareThumbnailCard(asset: asset, fileURL: nil, refreshToken: token, isSelected: true, isViewed: false)
        let refreshed = AssetCompareThumbnailCard(asset: asset, fileURL: nil, refreshToken: UUID(), isSelected: false, isViewed: false)
        #expect(card == same)
        #expect(card != selected)
        #expect(card != refreshed)
    }

    private func fixtureAsset() -> AssetRecord {
        AssetRecord(libraryID: UUID(), filename: "test.png", relativePath: "test.png",
            format: .png, fileSizeBytes: 1, width: 6000, height: 4000)
    }

    private func request() -> ThumbnailLoadRequest {
        ThumbnailLoadRequest(assetID: UUID(), fileURL: URL(fileURLWithPath: "/test/\(UUID()).png"),
            fileSizeBytes: 1, modificationDate: nil, maxPixelSize: 520, refreshToken: UUID())
    }
}

/// AppKit's dirty-state getter includes ancestor/layer damage and is not cleared
/// by writing false on an unpresented window. Observe actual redraw requests,
/// while forwarding to AppKit, to separate our changes from window damage.
@MainActor
private final class InvalidationRecordingImageView: CompareAspectImageView {
    var invalidationRequests = 0

    override var needsDisplay: Bool {
        get { super.needsDisplay }
        set {
            if newValue { invalidationRequests += 1 }
            super.needsDisplay = newValue
        }
    }
}
