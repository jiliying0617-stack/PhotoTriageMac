import Foundation
import PhotoTriageCore
import Testing
#if canImport(AppKit)
import AppKit
import ImageIO
#endif
@testable import PhotoTriageUI

struct ThumbnailRendererTests {
#if canImport(AppKit)
    @Test
    func thumbnailKeepsRenderableImageSizeForCompareFitLayout() throws {
        let fileURL = try makeFixtureImage(
            width: 1521,
            height: 2048,
            filename: "compare-render-source.png"
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let thumbnail = try #require(
            PhotoImagePipeline.thumbnail(for: fileURL, maxPixelSize: 3200)
        )

        #expect(thumbnail.size.width > 0)
        #expect(thumbnail.size.height > 0)
        #expect(abs((thumbnail.size.width / thumbnail.size.height) - (1521.0 / 2048.0)) < 0.01)
    }

    @Test
    func thumbnailRespectsRequestedMaxPixelSize() throws {
        let fileURL = try makeFixtureImage(
            width: 2400,
            height: 1600,
            filename: "compare-render-max-pixel.png"
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let thumbnail = try #require(
            PhotoImagePipeline.thumbnail(for: fileURL, maxPixelSize: 800)
        )

        #expect(max(thumbnail.size.width, thumbnail.size.height) <= 800.0)
    }

    @Test
    func fullResolutionCompareRequestPreservesSourcePixelDimensions() throws {
        let fileURL = try makeFixtureImage(
            width: 2400,
            height: 1600,
            filename: "compare-full-resolution.png"
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let image = try #require(
            PhotoImagePipeline.image(
                for: fileURL,
                maxPixelSize: 2400,
                cachePolicy: .bypass
            )
        )

        #expect(image.size == CGSize(width: 2400, height: 1600))
    }

    @Test
    func rendererLoadsChinesePathJpegAndPngFixturesForCompare() throws {
        let jpegURL = try makeFixtureImage(
            width: 1951,
            height: 2048,
            filename: "第三波/原图/000021_input.jpg",
            bitmapType: .jpeg
        )
        let rootURL = jpegURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let pngURL = try makeFixtureImage(
            width: 1951,
            height: 2048,
            filename: "第三波/结果图/000021_input.png",
            bitmapType: .png,
            rootURL: rootURL
        )

        let jpegImage = try #require(PhotoImagePipeline.image(for: jpegURL, maxPixelSize: 2048))
        let pngImage = try #require(PhotoImagePipeline.image(for: pngURL, maxPixelSize: 2048))

        #expect(jpegImage.size.width > 0)
        #expect(jpegImage.size.height > 0)
        #expect(pngImage.size.width > 0)
        #expect(pngImage.size.height > 0)
    }

    @Test
    func compareImageLoaderAppliesExifOrientationTransform() throws {
        let fileURL = try makeOrientedJPEG(width: 40, height: 20, orientation: 6)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let image = try #require(PhotoImagePipeline.image(for: fileURL, maxPixelSize: 400, cachePolicy: .bypass))

        #expect(image.size.width == 20)
        #expect(image.size.height == 40)
    }

    @Test
    func compareImageCacheCanBeReadSynchronouslyWithoutRedecoding() throws {
        let fileURL = try makeFixtureImage(
            width: 1600,
            height: 1200,
            filename: "compare-synchronous-cache.png"
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let loadedImage = try #require(
            PhotoImagePipeline.image(
                for: fileURL,
                maxPixelSize: 3200,
                cachePolicy: .refresh
            )
        )
        let cachedImage = try #require(
            PhotoImagePipeline.cachedImage(for: fileURL, maxPixelSize: 3200)
        )

        #expect(cachedImage === loadedImage)
    }

    @Test
    func compareImageCacheProvidesLowerResolutionFrameDuringQualityUpgrade() throws {
        let fileURL = try makeFixtureImage(
            width: 2400,
            height: 1600,
            filename: "compare-progressive-preview.png"
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let preview = try #require(
            PhotoImagePipeline.image(
                for: fileURL,
                maxPixelSize: 1024,
                cachePolicy: .refresh
            )
        )
        let cachedPreview = try #require(PhotoImagePipeline.cachedPreviewImage(for: fileURL))

        #expect(cachedPreview === preview)
        #expect(PhotoImagePipeline.cachedImage(for: fileURL, maxPixelSize: 2400) == nil)
    }

    @Test
    func compareGIFExporterWritesLoopingFramesInCompareOrder() throws {
        let firstURL = try makeFixtureImage(width: 80, height: 60, filename: "gif-a.png")
        let rootURL = firstURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let secondURL = try makeFixtureImage(width: 80, height: 60, filename: "gif-b.png", rootURL: rootURL)
        let library = LibraryFolder(displayName: "GIF", path: rootURL.path, columnIndex: 0)
        let assets = [
            AssetRecord(
                libraryID: library.id,
                filename: "gif-a.png",
                relativePath: "gif-a.png",
                format: .png,
                fileSizeBytes: 100,
                width: 80,
                height: 60
            ),
            AssetRecord(
                libraryID: library.id,
                filename: "gif-b.png",
                relativePath: "gif-b.png",
                format: .png,
                fileSizeBytes: 100,
                width: 80,
                height: 60
            )
        ]
        let outputURL = rootURL.appendingPathComponent("compare.gif")

        try CompareGIFExporter.writeGIF(
            items: [
                CompareGIFExportItem(asset: assets[0], fileURL: firstURL),
                CompareGIFExportItem(asset: assets[1], fileURL: secondURL)
            ],
            request: CompareGIFExportRequest(
                viewport: CGSize(width: 120, height: 90),
                zoomScale: 2,
                pan: CGSize(width: 0.4, height: -0.2),
                contentInset: 0
            ),
            to: outputURL
        )

        let source = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)

        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect(gifProperties?[kCGImagePropertyGIFLoopCount] as? Int == 0)
    }

    @Test
    func compareGIFExporterUsesSameFlippedViewportCoordinatesAsCompareView() throws {
        let fileURL = try makeQuadrantFixtureImage(width: 100, height: 100, filename: "quadrants.png")
        let rootURL = fileURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let library = LibraryFolder(displayName: "GIF", path: rootURL.path, columnIndex: 0)
        let asset = AssetRecord(
            libraryID: library.id,
            filename: "quadrants.png",
            relativePath: "quadrants.png",
            format: .png,
            fileSizeBytes: 100,
            width: 100,
            height: 100
        )
        let outputURL = rootURL.appendingPathComponent("quadrants.gif")

        try CompareGIFExporter.writeGIF(
            items: [
                CompareGIFExportItem(asset: asset, fileURL: fileURL),
                CompareGIFExportItem(asset: asset, fileURL: fileURL)
            ],
            request: CompareGIFExportRequest(
                viewport: CGSize(width: 50, height: 50),
                zoomScale: 2,
                pan: CGSize(width: 0, height: 1),
                contentInset: 0
            ),
            to: outputURL
        )

        let source = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let frame = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let centerColor = try #require(centerPixelColor(in: frame))

        #expect(centerColor.blue > 0.70)
        #expect(centerColor.red < 0.20)
        #expect(centerColor.green < 0.20)
    }

    @Test
    func compareGIFExporterKeepsViewportResolutionWithoutDownscaling() throws {
        let fileURL = try makeFixtureImage(width: 2200, height: 1400, filename: "large-gif-source.png")
        let rootURL = fileURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let library = LibraryFolder(displayName: "GIF", path: rootURL.path, columnIndex: 0)
        let asset = AssetRecord(
            libraryID: library.id,
            filename: "large-gif-source.png",
            relativePath: "large-gif-source.png",
            format: .png,
            fileSizeBytes: 100,
            width: 2200,
            height: 1400
        )
        let outputURL = rootURL.appendingPathComponent("large.gif")

        try CompareGIFExporter.writeGIF(
            items: [
                CompareGIFExportItem(asset: asset, fileURL: fileURL),
                CompareGIFExportItem(asset: asset, fileURL: fileURL)
            ],
            request: CompareGIFExportRequest(
                viewport: CGSize(width: 1800, height: 1100),
                zoomScale: 1,
                pan: .zero,
                contentInset: 0
            ),
            to: outputURL
        )

        let source = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let frame = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(frame.width >= 1800)
        #expect(frame.height >= 1100)
    }

    @Test
    func compareGIFExporterUsesSourcePixelResolutionForSmallViewport() throws {
        let fileURL = try makeFixtureImage(width: 2200, height: 1400, filename: "source-resolution-gif.png")
        let rootURL = fileURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let library = LibraryFolder(displayName: "GIF", path: rootURL.path, columnIndex: 0)
        let asset = AssetRecord(
            libraryID: library.id,
            filename: "source-resolution-gif.png",
            relativePath: "source-resolution-gif.png",
            format: .png,
            fileSizeBytes: 100,
            width: 2200,
            height: 1400
        )
        let outputURL = rootURL.appendingPathComponent("source-resolution.gif")

        try CompareGIFExporter.writeGIF(
            items: [
                CompareGIFExportItem(asset: asset, fileURL: fileURL),
                CompareGIFExportItem(asset: asset, fileURL: fileURL)
            ],
            request: CompareGIFExportRequest(
                viewport: CGSize(width: 550, height: 350),
                zoomScale: 1,
                pan: .zero,
                contentInset: 0
            ),
            to: outputURL
        )

        let source = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let frame = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(frame.width >= 2200)
        #expect(frame.height >= 1400)
    }

    private func makeFixtureImage(
        width: Int,
        height: Int,
        filename: String,
        bitmapType: NSBitmapImageRep.FileType = .png,
        rootURL: URL? = nil
    ) throws -> URL {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(
            calibratedRed: 0.26,
            green: 0.48,
            blue: 0.82,
            alpha: 1
        ).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        let data = try #require(rep.representation(using: bitmapType, properties: [:]))
        let fileURL = (rootURL ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            .appendingPathComponent(filename)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL)
        return fileURL
    }

    private func makeOrientedJPEG(width: Int, height: Int, orientation: Int) throws -> URL {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        let cgImage = try #require(rep.cgImage)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("oriented.jpg")
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                fileURL as CFURL,
                "public.jpeg" as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(
            destination,
            cgImage,
            [kCGImagePropertyOrientation: orientation] as CFDictionary
        )
        try #require(CGImageDestinationFinalize(destination))
        return fileURL
    }

    private func makeQuadrantFixtureImage(width: Int, height: Int, filename: String) throws -> URL {
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let halfWidth = CGFloat(width) * 0.5
        let halfHeight = CGFloat(height) * 0.5
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: halfWidth, height: halfHeight)).fill()
        NSColor.green.setFill()
        NSBezierPath(rect: NSRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight)).fill()
        NSColor.blue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight)).fill()
        NSColor.yellow.setFill()
        NSBezierPath(rect: NSRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight)).fill()
        NSGraphicsContext.restoreGraphicsState()

        let data = try #require(rep.representation(using: .png, properties: [:]))
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(filename)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL)
        return fileURL
    }

    private func centerPixelColor(in image: CGImage) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        let width = image.width
        let height = image.height
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.translateBy(x: CGFloat(1 - width / 2), y: CGFloat(1 - height / 2))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: CGFloat(pixel[3]) / 255
        )
    }
#endif
}
