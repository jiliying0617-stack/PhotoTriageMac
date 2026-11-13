import CoreGraphics
import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
import Testing
@testable import PhotoTriageCore

struct AssetMetadataReaderTests {
#if canImport(ImageIO)
    @Test
    func metadataAppliesExifOrientationWhenReportingDisplayDimensions() throws {
        let fileURL = try makeOrientedJPEG(width: 40, height: 20, orientation: 6)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let metadata = try #require(AssetMetadataReader.metadata(for: fileURL))

        #expect(metadata.width == 20)
        #expect(metadata.height == 40)
    }

    private func makeOrientedJPEG(width: Int, height: Int, orientation: Int) throws -> URL {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )

        context.setFillColor(CGColor(red: 0.18, green: 0.44, blue: 0.86, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let cgImage = try #require(context.makeImage())
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
#endif
}
