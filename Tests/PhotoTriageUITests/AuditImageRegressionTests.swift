import AppKit
import Foundation
import ImageIO
import PhotoTriageCore
import Testing
@testable import PhotoTriageUI

struct AuditImageRegressionTests {
    @Test func fourJPEGRotationsPreserveDecodedPixelsAndKeepOriginalBackup() throws {
        let root = try imageRegressionDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("texture.jpg")
        let backups = root.appendingPathComponent("backups")
        try imageRegressionWrite(url, width: 256, height: 192, noisy: true, jpeg: true)
        let originalBytes = try Data(contentsOf: url)
        let before = try #require(PhotoImagePipeline.fullResolutionCGImage(for: url))
        let rotation = FileSystemAssetRotationService(backupRoot: backups)
        try rotation.rotateFile(at: url, quarterTurns: 1)
        #expect(PhotoImagePipeline.pixelSize(for: url) == CGSize(width: 192, height: 256))
        for _ in 0..<3 { try rotation.rotateFile(at: url, quarterTurns: 1) }
        let after = try #require(PhotoImagePipeline.fullResolutionCGImage(for: url))
        #expect(imageRegressionPixels(before) == imageRegressionPixels(after))
        let folders = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        let backup = try #require(folders.first).appendingPathComponent("texture.jpg")
        #expect(try Data(contentsOf: backup) == originalBytes)
    }

    @Test func overwritingFileInvalidatesEverySizeAndPreview() throws {
        let root = try imageRegressionDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("image.png")
        try imageRegressionWrite(url, width: 256, height: 192)
        let old = try #require(PhotoImagePipeline.image(for: url, maxPixelSize: 128))
        try imageRegressionWrite(url, width: 256, height: 192, red: true)
        _ = PhotoImagePipeline.image(for: url, maxPixelSize: 256, cachePolicy: .refresh)
        let current = try #require(PhotoImagePipeline.image(for: url, maxPixelSize: 128))
        let uncached = try #require(PhotoImagePipeline.image(for: url, maxPixelSize: 128, cachePolicy: .bypass))
        let oldCG = try #require(old.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let currentCG = try #require(current.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let uncachedCG = try #require(uncached.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(imageRegressionPixels(currentCG) != imageRegressionPixels(oldCG))
        #expect(imageRegressionPixels(currentCG) == imageRegressionPixels(uncachedCG))
        #expect(PhotoImagePipeline.cachedPreviewImage(for: url) != nil)
    }

    @Test func nativeToleranceFindsOneChannelStepBeyond4096Pixels() throws {
        let root = try imageRegressionDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = root.appendingPathComponent("base.png")
        let overlay = root.appendingPathComponent("overlay.png")
        try imageRegressionWrite(base, width: 8192, height: 64, tinyDifference: false)
        try imageRegressionWrite(overlay, width: 8192, height: 64, tinyDifference: true)
        let analysis = try CompareToleranceRenderer.analyze(baseFileURL: base, baseRotationDegrees: 0,
            overlayFileURL: overlay, overlayRotationDegrees: 0, originalResolution: true)
        #expect(analysis.width == 8192)
        #expect(analysis.maximumDifference == 1)
        #expect(analysis.differenceHistogram[1] == 1)
        let visible = try #require(try CompareToleranceRenderer.render(analysis: analysis, tolerance: 0))
        #expect(visible.differingPixelCount == 1)
        #expect(visible.totalPixelCount == 8192 * 64)
        let bytes = imageRegressionPixels(visible.image)
        #expect(stride(from: 0, to: bytes.count, by: 4).contains { bytes[$0] == 255 && bytes[$0 + 1] == 0 && bytes[$0 + 2] == 0 })
        let accepted = try #require(try CompareToleranceRenderer.render(analysis: analysis, tolerance: 1))
        #expect(accepted.differingPixelCount == 0)
    }

    @Test func cancelledDecodeDoesNotPopulateCache() async throws {
        let root = try imageRegressionDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("cancelled.png")
        try imageRegressionWrite(url, width: 256, height: 192)
        #expect(PhotoImagePipeline.image(for: url, maxPixelSize: 64, shouldContinue: { false }) == nil)
        #expect(PhotoImagePipeline.cachedImage(for: url, maxPixelSize: 64) == nil)
        #expect(throws: CancellationError.self) {
            try CompareToleranceRenderer.analyze(baseFileURL: url, baseRotationDegrees: 0,
                overlayFileURL: url, overlayRotationDegrees: 0, shouldContinue: { false })
        }
    }

    @Test func displayMaskHasBoundedMemoryWithoutLosingDifferenceCount() throws {
        let count = 3072 * 2048
        var differences = [UInt8](repeating: 0, count: count)
        differences[count - 1] = 1
        var histogram = [Int](repeating: 0, count: 256)
        histogram[0] = count - 1
        histogram[1] = 1
        let analysis = CompareToleranceAnalysis(width: 3072, height: 2048,
            differences: differences, backgroundGrayscale: [UInt8](repeating: 12, count: count),
            maximumDifference: 1, differenceHistogram: histogram)
        let result = try #require(try CompareToleranceRenderer.render(analysis: analysis))
        #expect(result.image.bytesPerRow * result.image.height <= 16 * 1024 * 1024)
        #expect(result.differingPixelCount == 1)
        #expect(result.totalPixelCount == count)
    }
}

private func imageRegressionDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoTriageImageRegression-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
private func imageRegressionWrite(_ url: URL, width: Int, height: Int, noisy: Bool = false,
    jpeg: Bool = false, red: Bool = false, tinyDifference: Bool? = nil) throws {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for i in 0..<(width * height) {
        let x = i % width, y = i / width
        bytes[i * 4] = noisy ? UInt8((x * 17 + y * 23) % 256) : (red ? 240 : 10)
        bytes[i * 4 + 1] = noisy ? UInt8((x * 7 + y * 43) % 256) : 10
        bytes[i * 4 + 2] = noisy ? UInt8((x * 3 + y * 13) % 256) : (red ? 10 : 240)
        if tinyDifference != nil { bytes[i * 4] = 0; bytes[i * 4 + 1] = 0; bytes[i * 4 + 2] = 0 }
    }
    if tinyDifference == true { bytes[(width * 32 + 4097) * 4] = 1 }
    let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, (jpeg ? "public.jpeg" : "public.png") as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
}
private func imageRegressionPixels(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
}
