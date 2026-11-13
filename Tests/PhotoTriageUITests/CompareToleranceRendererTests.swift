import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import PhotoTriageUI

struct CompareToleranceRendererTests {
    @Test
    func existingProjectPNGCanBeRendered() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let imageURL = projectRoot
            .appendingPathComponent("Assets/AppIcon.iconset/icon_512x512.png")

        let result = try CompareToleranceRenderer.render(
            baseFileURL: imageURL,
            baseRotationDegrees: 0,
            overlayFileURL: imageURL,
            overlayRotationDegrees: 0
        )

        #expect(result.maximumDifference == 0)
        #expect(result.differingPixelCount == 0)
        #expect(result.totalPixelCount == 512 * 512)
    }

    @Test
    func existingProjectPNGCanBeRenderedOnBackgroundQueue() async throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let imageURL = projectRoot
            .appendingPathComponent("Assets/AppIcon.iconset/icon_512x512.png")

        let result = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let rendered = Result {
                    try CompareToleranceRenderer.render(
                        baseFileURL: imageURL,
                        baseRotationDegrees: 0,
                        overlayFileURL: imageURL,
                        overlayRotationDegrees: 0
                    )
                }
                continuation.resume(with: rendered)
            }
        }

        #expect(result.maximumDifference == 0)
        #expect(result.differingPixelCount == 0)
    }

    @Test
    func identicalImagesHaveNoDifference() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("same.png")
        try writePNG(
            pixels: [
                20, 40, 60, 255,
                180, 140, 100, 255,
            ],
            width: 2,
            height: 1,
            to: imageURL
        )

        let result = try CompareToleranceRenderer.render(
            baseFileURL: imageURL,
            baseRotationDegrees: 0,
            overlayFileURL: imageURL,
            overlayRotationDegrees: 0
        )

        #expect(result.maximumDifference == 0)
        #expect(result.differingPixelCount == 0)
        #expect(result.totalPixelCount == 2)
    }

    @Test
    func changedPixelIsCountedAndReportsMaximumChannelDifference() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseURL = directory.appendingPathComponent("base.png")
        let overlayURL = directory.appendingPathComponent("overlay.png")
        try writePNG(
            pixels: [
                0, 0, 0, 255,
                80, 100, 120, 255,
            ],
            width: 2,
            height: 1,
            to: baseURL
        )
        try writePNG(
            pixels: [
                255, 0, 0, 255,
                80, 100, 120, 255,
            ],
            width: 2,
            height: 1,
            to: overlayURL
        )

        let result = try CompareToleranceRenderer.render(
            baseFileURL: baseURL,
            baseRotationDegrees: 0,
            overlayFileURL: overlayURL,
            overlayRotationDegrees: 0,
            tolerance: 0
        )

        #expect(result.maximumDifference == 255)
        #expect(result.differingPixelCount == 1)
        #expect(result.totalPixelCount == 2)
        #expect(result.differencePercentageText == "50.00%")
    }

    @Test
    func increasingToleranceMonotonicallyReducesAboveToleranceDifferences() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseURL = directory.appendingPathComponent("base.png")
        let overlayURL = directory.appendingPathComponent("overlay.png")
        try writePNG(
            pixels: [
                0, 0, 0, 255,
                0, 0, 0, 255,
                0, 0, 0, 255,
                0, 0, 0, 255,
            ],
            width: 4,
            height: 1,
            to: baseURL
        )
        try writePNG(
            pixels: [
                1, 0, 0, 255,
                32, 0, 0, 255,
                64, 0, 0, 255,
                128, 0, 0, 255,
            ],
            width: 4,
            height: 1,
            to: overlayURL
        )

        let minimumTolerance = try CompareToleranceRenderer.render(
            baseFileURL: baseURL,
            baseRotationDegrees: 0,
            overlayFileURL: overlayURL,
            overlayRotationDegrees: 0,
            tolerance: 0
        )
        let middleTolerance = try CompareToleranceRenderer.render(
            baseFileURL: baseURL,
            baseRotationDegrees: 0,
            overlayFileURL: overlayURL,
            overlayRotationDegrees: 0,
            tolerance: 64
        )
        let maximumTolerance = try CompareToleranceRenderer.render(
            baseFileURL: baseURL,
            baseRotationDegrees: 0,
            overlayFileURL: overlayURL,
            overlayRotationDegrees: 0,
            tolerance: 255
        )

        #expect(minimumTolerance.maximumDifference == 128)
        #expect(minimumTolerance.differingPixelCount == 4)
        #expect(middleTolerance.differingPixelCount == 1)
        #expect(maximumTolerance.differingPixelCount == 0)
        #expect(minimumTolerance.differingPixelCount > middleTolerance.differingPixelCount)
        #expect(middleTolerance.differingPixelCount > maximumTolerance.differingPixelCount)

        let middleData = try #require(middleTolerance.image.dataProvider?.data)
        let middlePixels = [UInt8](middleData as Data)
        #expect(middlePixels[0] == 38)
        #expect(middlePixels[1] == 105)
        #expect(middlePixels[2] == 255)
        #expect(middlePixels[8] == 38)
        #expect(middlePixels[9] == 105)
        #expect(middlePixels[10] == 255)
        #expect(middlePixels[12] == 255)
        #expect(middlePixels[13] == 0)
        #expect(middlePixels[14] == 0)

        let maximumData = try #require(maximumTolerance.image.dataProvider?.data)
        let maximumPixels = [UInt8](maximumData as Data)
        #expect(maximumPixels[0] == 38)
        #expect(maximumPixels[1] == 105)
        #expect(maximumPixels[2] == 255)
    }

    @Test
    func oneAnalysisPassCanRenderMultipleToleranceValuesWithoutReadingFilesAgain() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseURL = directory.appendingPathComponent("base.png")
        let overlayURL = directory.appendingPathComponent("overlay.png")
        try writePNG(
            pixels: [
                0, 0, 0, 255,
                0, 0, 0, 255,
                0, 0, 0, 255,
            ],
            width: 3,
            height: 1,
            to: baseURL
        )
        try writePNG(
            pixels: [
                8, 0, 0, 255,
                64, 0, 0, 255,
                192, 0, 0, 255,
            ],
            width: 3,
            height: 1,
            to: overlayURL
        )

        let analysis = try CompareToleranceRenderer.analyze(
            baseFileURL: baseURL,
            baseRotationDegrees: 0,
            overlayFileURL: overlayURL,
            overlayRotationDegrees: 0
        )

        try FileManager.default.removeItem(at: baseURL)
        try FileManager.default.removeItem(at: overlayURL)

        let lowTolerance = try #require(
            try CompareToleranceRenderer.render(analysis: analysis, tolerance: 8)
        )
        let highTolerance = try #require(
            try CompareToleranceRenderer.render(analysis: analysis, tolerance: 192)
        )

        #expect(lowTolerance.maximumDifference == 192)
        #expect(lowTolerance.differingPixelCount == 2)
        #expect(highTolerance.differingPixelCount == 0)
        #expect(lowTolerance.totalPixelCount == highTolerance.totalPixelCount)
    }

    @Test
    func subToleranceBlueCanBeHidden() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseURL = directory.appendingPathComponent("base.png")
        let overlayURL = directory.appendingPathComponent("overlay.png")
        try writePNG(
            pixels: [
                0, 0, 0, 255,
                0, 0, 0, 255,
            ],
            width: 2,
            height: 1,
            to: baseURL
        )
        try writePNG(
            pixels: [
                10, 0, 0, 255,
                100, 0, 0, 255,
            ],
            width: 2,
            height: 1,
            to: overlayURL
        )

        let result = try CompareToleranceRenderer.render(
            baseFileURL: baseURL,
            baseRotationDegrees: 0,
            overlayFileURL: overlayURL,
            overlayRotationDegrees: 0,
            tolerance: 50,
            showsSubToleranceDifferences: false
        )
        let imageData = try #require(result.image.dataProvider?.data)
        let pixels = [UInt8](imageData as Data)

        #expect(pixels[0] == 0)
        #expect(pixels[1] == 0)
        #expect(pixels[2] == 0)
        #expect(pixels[4] == 255)
        #expect(pixels[5] == 0)
        #expect(pixels[6] == 0)
    }

    @Test
    func rendererPreservesPixelGridThrough4096Pixels() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("wide.png")
        let pixels = [UInt8](repeating: 0, count: 4096 * 4)
        try writePNG(pixels: pixels, width: 4096, height: 1, to: imageURL)

        let result = try CompareToleranceRenderer.render(
            baseFileURL: imageURL,
            baseRotationDegrees: 0,
            overlayFileURL: imageURL,
            overlayRotationDegrees: 0
        )

        #expect(CompareToleranceRenderer.maximumComparisonDimension == 4096)
        #expect(result.image.width == 4096)
        #expect(result.image.height == 1)
        #expect(result.totalPixelCount == 4096)
    }

    @Test
    func alphaOnlyChangesAreDetected() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseURL = directory.appendingPathComponent("base.png")
        let overlayURL = directory.appendingPathComponent("overlay.png")
        try writePNG(pixels: [0, 0, 0, 255], width: 1, height: 1, to: baseURL)
        try writePNG(pixels: [0, 0, 0, 128], width: 1, height: 1, to: overlayURL)

        let result = try CompareToleranceRenderer.render(
            baseFileURL: baseURL,
            baseRotationDegrees: 0,
            overlayFileURL: overlayURL,
            overlayRotationDegrees: 0,
            tolerance: 0
        )

        #expect(result.maximumDifference == 127)
        #expect(result.differingPixelCount == 1)
    }

    @Test
    func mismatchedPixelDimensionsAreRejectedInsteadOfResampled() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseURL = directory.appendingPathComponent("base.png")
        let overlayURL = directory.appendingPathComponent("overlay.png")
        try writePNG(pixels: [0, 0, 0, 255], width: 1, height: 1, to: baseURL)
        try writePNG(
            pixels: [
                0, 0, 0, 255,
                0, 0, 0, 255,
            ],
            width: 2,
            height: 1,
            to: overlayURL
        )

        #expect(throws: (any Error).self) {
            try CompareToleranceRenderer.render(
                baseFileURL: baseURL,
                baseRotationDegrees: 0,
                overlayFileURL: overlayURL,
                overlayRotationDegrees: 0,
                tolerance: 255
            )
        }
    }

    @Test
    func unchangedAreasUseAGrayscaleBaseImage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("color.png")
        try writePNG(pixels: [20, 80, 200, 255], width: 1, height: 1, to: imageURL)

        let result = try CompareToleranceRenderer.render(
            baseFileURL: imageURL,
            baseRotationDegrees: 0,
            overlayFileURL: imageURL,
            overlayRotationDegrees: 0
        )
        let imageData = try #require(result.image.dataProvider?.data)
        let pixels = [UInt8](imageData as Data)

        #expect(pixels[0] == pixels[1])
        #expect(pixels[1] == pixels[2])
        #expect(pixels[3] == 255)
    }

    @Test
    func unchangedGrayscaleBackgroundIsDarkEnoughForDifferenceColors() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageURL = directory.appendingPathComponent("white.png")
        try writePNG(pixels: [255, 255, 255, 255], width: 1, height: 1, to: imageURL)

        let result = try CompareToleranceRenderer.render(
            baseFileURL: imageURL,
            baseRotationDegrees: 0,
            overlayFileURL: imageURL,
            overlayRotationDegrees: 0
        )
        let imageData = try #require(result.image.dataProvider?.data)
        let pixels = [UInt8](imageData as Data)

        #expect(CompareToleranceRenderer.unchangedBackgroundLuminanceScale == 0.36)
        #expect(pixels[0] == 92)
        #expect(pixels[1] == 92)
        #expect(pixels[2] == 92)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTriageToleranceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writePNG(pixels: [UInt8], width: Int, height: Int, to url: URL) throws {
        let data = Data(pixels) as CFData
        let provider = try #require(CGDataProvider(data: data))
        let image = try #require(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
        let destination = try #require(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
