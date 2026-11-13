import AppKit
import ImageIO
import PhotoTriageCore
import Testing
import UniformTypeIdentifiers
@testable import PhotoTriageUI

struct RenderingPerformanceRegressionTests {
    @MainActor @Test func completedGIFWindowClosesBeforeControllerIsReleased() {
        let controller = CompareGIFExportProgressWindowController(totalFrames: 2)
        controller.show()
        #expect(controller.isVisible)
        controller.complete()
        #expect(controller.isCompleted)
        #expect(!controller.isVisible)
        controller.update(CompareGIFExportProgress(completedFrames: 1, totalFrames: 2, message: "delayed"))
        #expect(!controller.isVisible)
    }

    @MainActor @Test func compareLifecycleDoesNotReplaceSwiftUIWindowDelegate() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let delegate = RenderingWindowDelegate()
        window.delegate = delegate
        var closeCount = 0
        let coordinator = CompareWindowLifecycleObserver.Coordinator { closeCount += 1 }
        coordinator.attach(to: window)
        coordinator.attach(to: window)
        #expect(window.delegate === delegate)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        #expect(closeCount == 1)
        coordinator.detach()
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        #expect(closeCount == 1)
        window.close()
    }

    @Test func invalidGIFRequestDoesNotReplaceExistingExport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("existing.gif")
        let original = Data("existing export".utf8)
        try original.write(to: output)
        let asset = AssetRecord(libraryID: UUID(), filename: "missing.png", relativePath: "missing.png",
            format: .png, fileSizeBytes: 0, width: 100_000, height: 100_000)
        let items = [CompareGIFExportItem(asset: asset, fileURL: root.appendingPathComponent("missing.png"))]
        for size in [CGSize(width: CGFloat.nan, height: 100), CGSize(width: 100_000, height: 100_000)] {
            #expect(throws: (any Error).self) {
                try CompareGIFExporter.writeGIF(items: items, request: CompareGIFExportRequest(
                    viewport: size, zoomScale: 1, pan: .zero, contentInset: 0), to: output)
            }
            #expect(try Data(contentsOf: output) == original)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["existing.gif"])
    }

    @Test func failedGIFFrameLeavesExistingOutputAndNoTemporaryFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("existing.gif")
        let original = Data("existing export".utf8)
        try original.write(to: output)
        let asset = AssetRecord(libraryID: UUID(), filename: "missing.png", relativePath: "missing.png",
            format: .png, fileSizeBytes: 0, width: 100, height: 100)
        #expect(throws: (any Error).self) {
            try CompareGIFExporter.writeGIF(items: [CompareGIFExportItem(asset: asset, fileURL: root.appendingPathComponent("missing.png"))],
                request: CompareGIFExportRequest(viewport: CGSize(width: 100, height: 100), zoomScale: 1, pan: .zero, contentInset: 0), to: output)
        }
        #expect(try Data(contentsOf: output) == original)
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(remainingFiles == ["existing.gif"])
    }

    @Test func malformedToleranceDimensionsFailWithoutIntegerOverflow() throws {
        let analysis = CompareToleranceAnalysis(width: Int.max, height: 2, differences: [],
            backgroundGrayscale: [], maximumDifference: 0, differenceHistogram: Array(repeating: 0, count: 256))
        #expect(throws: (any Error).self) { try CompareToleranceRenderer.render(analysis: analysis) }
    }

    @Test func malformedToleranceDisplayCacheIsRejected() throws {
        let analysis = CompareToleranceAnalysis(width: 1, height: 1, differences: [0],
            backgroundGrayscale: [0], maximumDifference: 0, differenceHistogram: [1] + Array(repeating: 0, count: 255),
            displayPixels: CompareToleranceDisplayPixels(width: 2, height: 2, differences: [], grayscale: []))
        #expect(throws: (any Error).self) { try CompareToleranceRenderer.render(analysis: analysis) }
    }

    @Test func repeatedToleranceSliderRenderingBenchmark() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.png")
        let second = root.appendingPathComponent("second.png")
        try writeRenderingFixture(to: first, width: 2048, height: 1536, red: 0.25)
        try writeRenderingFixture(to: second, width: 2048, height: 1536, red: 0.5)
        let analysis = try CompareToleranceRenderer.analyze(baseFileURL: first, baseRotationDegrees: 0,
            overlayFileURL: second, overlayRotationDegrees: 0)
        let clock = ContinuousClock()
        let start = clock.now
        var checksum = 0
        for threshold in 0..<12 {
            checksum += try autoreleasepool {
                let result = try #require(try CompareToleranceRenderer.render(analysis: analysis, tolerance: threshold))
                return result.differingPixelCount
            }
        }
        #expect(checksum == 12 * 2048 * 1536)
        print("PERF tolerance 2048x1536 / 12 slider renders: \(start.duration(to: clock.now))")
    }

    @Test func gifDitherRenderingBenchmark() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.png")
        try writeRenderingFixture(to: source, width: 1600, height: 1000, red: 0.3)
        let asset = AssetRecord(libraryID: UUID(), filename: "source.png", relativePath: "source.png",
            format: .png, fileSizeBytes: 100, width: 1600, height: 1000)
        let items = Array(repeating: CompareGIFExportItem(asset: asset, fileURL: source), count: 3)
        let output = root.appendingPathComponent("export.gif")
        let clock = ContinuousClock()
        let start = clock.now
        try CompareGIFExporter.writeGIF(items: items, request: CompareGIFExportRequest(
            viewport: CGSize(width: 1600, height: 1000), zoomScale: 1, pan: .zero, contentInset: 0), to: output)
        let decoded = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(decoded) == 3)
        print("PERF GIF 1600x1000 / 3 frames: \(start.duration(to: clock.now))")
    }
}

@MainActor private final class RenderingWindowDelegate: NSObject, NSWindowDelegate {}

func writeRenderingFixture(to url: URL, width: Int, height: Int, red: CGFloat) throws {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}
