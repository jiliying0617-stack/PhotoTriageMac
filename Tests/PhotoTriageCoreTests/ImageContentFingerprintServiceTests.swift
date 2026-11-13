import CoreGraphics
import Foundation
import ImageIO
import PhotoTriageCore
import Testing

struct ImageContentFingerprintServiceTests {
    @Test
    func matchesRenamedSameContentAcrossFormatsAndRejectsDifferentImage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTriageFingerprint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("source.png")
        let renamedURL = root.appendingPathComponent("renamed-output.jpg")
        let differentURL = root.appendingPathComponent("different.png")
        try writeQuadrantImage(to: sourceURL, type: "public.png" as CFString, swapsColors: false)
        try writeQuadrantImage(to: renamedURL, type: "public.jpeg" as CFString, swapsColors: false)
        try writeQuadrantImage(to: differentURL, type: "public.png" as CFString, swapsColors: true)

        let sourceID = UUID()
        let renamedID = UUID()
        let differentID = UUID()
        let requests = [
            try request(assetID: sourceID, fileURL: sourceURL),
            try request(assetID: renamedID, fileURL: renamedURL),
            try request(assetID: differentID, fileURL: differentURL),
        ]
        let service = FileSystemImageContentFingerprintService(maximumConcurrentDecodes: 3)
        let fingerprints = await service.fingerprints(for: requests)

        let source = try #require(fingerprints[sourceID])
        let renamed = try #require(fingerprints[renamedID])
        let different = try #require(fingerprints[differentID])
        #expect(source.visualDifference(from: renamed) <= 0.18)
        #expect(source.visualDifference(from: different) > 0.18)
        #expect(ImageContentMatcher.bestMatches(
            referenceAssetIDs: [sourceID],
            targetAssetIDs: [differentID, renamedID],
            fingerprints: fingerprints
        ) == [sourceID: renamedID])
    }

    @Test
    func matcherShortlistsHundredsOfCandidatesWithoutLosingOneToOnePairs() {
        let pairCount = 500
        let referenceIDs = (0..<pairCount).map { _ in UUID() }
        let targetIDs = (0..<pairCount).map { _ in UUID() }
        var fingerprints: [UUID: ImageContentFingerprint] = [:]

        for index in 0..<pairCount {
            let fingerprint = syntheticFingerprint(seed: UInt64(index + 1))
            fingerprints[referenceIDs[index]] = fingerprint
            fingerprints[targetIDs[index]] = fingerprint
        }

        let clock = ContinuousClock()
        let startedAt = clock.now
        let matches = ImageContentMatcher.bestMatches(
            referenceAssetIDs: referenceIDs,
            targetAssetIDs: targetIDs,
            fingerprints: fingerprints
        )
        let elapsed = startedAt.duration(to: clock.now)

        #expect(matches.count == pairCount)
        #expect(referenceIDs.indices.allSatisfy { matches[referenceIDs[$0]] == targetIDs[$0] })
        #expect(elapsed < .seconds(3))
    }

    private func syntheticFingerprint(seed originalSeed: UInt64) -> ImageContentFingerprint {
        var seed = originalSeed &* 0x9e3779b97f4a7c15
        func nextValue() -> UInt64 {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return seed
        }

        return ImageContentFingerprint(
            edgeWords: (0..<8).map { _ in nextValue() },
            normalizedLuminance: (0..<256).map { _ in UInt8(truncatingIfNeeded: nextValue()) },
            meanRed: UInt8(truncatingIfNeeded: nextValue()),
            meanGreen: UInt8(truncatingIfNeeded: nextValue()),
            meanBlue: UInt8(truncatingIfNeeded: nextValue()),
            luminanceDeviation: 40,
            aspectRatio: 1,
            chrominance: (0..<512).map { _ in UInt8(truncatingIfNeeded: nextValue()) }
        )
    }

    private func request(assetID: UUID, fileURL: URL) throws -> ImageContentFingerprintRequest {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return ImageContentFingerprintRequest(
            assetID: assetID,
            fileURL: fileURL,
            fileSizeBytes: Int64(values.fileSize ?? 0),
            contentModificationDate: values.contentModificationDate
        )
    }

    private func writeQuadrantImage(to url: URL, type: CFString, swapsColors: Bool) throws {
        let width = 160
        let height = 120
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))

        let colors: [CGColor] = swapsColors
            ? [CGColor(red: 0, green: 0, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 0, alpha: 1), CGColor(red: 0, green: 1, blue: 0, alpha: 1), CGColor(red: 1, green: 0, blue: 0, alpha: 1)]
            : [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 1, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 0, alpha: 1)]
        let rects = [
            CGRect(x: 0, y: 0, width: width / 2, height: height / 2),
            CGRect(x: width / 2, y: 0, width: width / 2, height: height / 2),
            CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2),
            CGRect(x: width / 2, y: height / 2, width: width / 2, height: height / 2),
        ]
        for (color, rect) in zip(colors, rects) {
            context.setFillColor(color)
            context.fill(rect)
        }

        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil))
        let properties: [CFString: Any] = type as String == "public.jpeg"
            ? [kCGImageDestinationLossyCompressionQuality: 0.82]
            : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
    }
}
