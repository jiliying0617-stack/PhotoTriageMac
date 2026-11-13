import CoreGraphics
import Foundation
import ImageIO
#if canImport(QuickLookThumbnailing)
import QuickLookThumbnailing
#endif

public struct ImageContentFingerprintRequest: Hashable, Sendable {
    public let assetID: UUID
    public let fileURL: URL
    public let fileSizeBytes: Int64
    public let contentModificationDate: Date?

    public init(
        assetID: UUID,
        fileURL: URL,
        fileSizeBytes: Int64,
        contentModificationDate: Date?
    ) {
        self.assetID = assetID
        self.fileURL = fileURL
        self.fileSizeBytes = fileSizeBytes
        self.contentModificationDate = contentModificationDate
    }
}

public struct ImageContentFingerprint: Hashable, Sendable {
    public let edgeWords: [UInt64]
    public let normalizedLuminance: [UInt8]
    public let meanRed: UInt8
    public let meanGreen: UInt8
    public let meanBlue: UInt8
    public let luminanceDeviation: UInt8
    public let aspectRatio: Double
    public let chrominance: [UInt8]

    public init(
        edgeWords: [UInt64],
        normalizedLuminance: [UInt8],
        meanRed: UInt8,
        meanGreen: UInt8,
        meanBlue: UInt8,
        luminanceDeviation: UInt8,
        aspectRatio: Double,
        chrominance: [UInt8] = []
    ) {
        self.edgeWords = edgeWords
        self.normalizedLuminance = normalizedLuminance
        self.meanRed = meanRed
        self.meanGreen = meanGreen
        self.meanBlue = meanBlue
        self.luminanceDeviation = luminanceDeviation
        self.aspectRatio = aspectRatio
        self.chrominance = chrominance
    }

    public func visualDifference(from other: ImageContentFingerprint) -> Double {
        guard aspectRatio > 0, other.aspectRatio > 0 else { return 1 }
        let aspectDifference = abs(log(aspectRatio / other.aspectRatio))
        guard aspectDifference <= 0.18 else { return 1 }

        let edgeDifference = normalizedEdgeDifference(from: other)

        let comparableSampleCount = min(normalizedLuminance.count, other.normalizedLuminance.count)
        let luminanceDifference: Double
        if comparableSampleCount > 0 {
            let totalDifference = zip(
                normalizedLuminance.prefix(comparableSampleCount),
                other.normalizedLuminance.prefix(comparableSampleCount)
            ).reduce(0) { result, samples in
                result + abs(Int(samples.0) - Int(samples.1))
            }
            luminanceDifference = Double(totalDifference) / Double(comparableSampleCount * 255)
        } else {
            luminanceDifference = 1
        }

        let colorDifference = Double(
            abs(Int(meanRed) - Int(other.meanRed))
                + abs(Int(meanGreen) - Int(other.meanGreen))
                + abs(Int(meanBlue) - Int(other.meanBlue))
        ) / (3 * 255)
        let comparableChrominanceCount = min(chrominance.count, other.chrominance.count)
        let chrominanceDifference: Double
        if comparableChrominanceCount > 0 {
            let totalDifference = zip(
                chrominance.prefix(comparableChrominanceCount),
                other.chrominance.prefix(comparableChrominanceCount)
            ).reduce(0) { result, samples in
                result + abs(Int(samples.0) - Int(samples.1))
            }
            chrominanceDifference = Double(totalDifference) / Double(comparableChrominanceCount * 255)
        } else {
            chrominanceDifference = 0
        }
        let textureStrength = max(luminanceDeviation, other.luminanceDeviation)
        if textureStrength < 6, colorDifference > 0.04 {
            return 1
        }

        let aspectPenalty = min(aspectDifference / 0.18, 1)
        return edgeDifference * 0.49
            + luminanceDifference * 0.24
            + chrominanceDifference * 0.20
            + colorDifference * 0.02
            + aspectPenalty * 0.05
    }

    fileprivate func coarseDifference(from other: ImageContentFingerprint) -> Double {
        guard aspectRatio > 0, other.aspectRatio > 0 else { return 1 }
        let relativeAspectDifference = abs(aspectRatio - other.aspectRatio) / max(aspectRatio, other.aspectRatio)
        guard relativeAspectDifference <= 0.165 else { return 1 }
        return normalizedEdgeDifference(from: other) + min(relativeAspectDifference / 0.165, 1) * 0.08
    }

    private func normalizedEdgeDifference(from other: ImageContentFingerprint) -> Double {
        let comparableWordCount = min(edgeWords.count, other.edgeWords.count)
        let comparableBitCount = comparableWordCount * 64
        guard comparableBitCount > 0 else { return 1 }
        var differingBitCount = 0
        for index in 0..<comparableWordCount {
            differingBitCount += (edgeWords[index] ^ other.edgeWords[index]).nonzeroBitCount
        }
        return Double(differingBitCount) / Double(comparableBitCount)
    }
}

public protocol ImageContentFingerprinting: Sendable {
    func fingerprints(
        for requests: [ImageContentFingerprintRequest]
    ) async -> [UUID: ImageContentFingerprint]
}

public enum ImageContentMatcher {
    public static func bestMatches(
        referenceAssetIDs: [UUID],
        targetAssetIDs: [UUID],
        fingerprints: [UUID: ImageContentFingerprint],
        maximumDifference: Double = 0.18
    ) -> [UUID: UUID] {
        let references = referenceAssetIDs.filter { fingerprints[$0] != nil }
        let targets = targetAssetIDs.filter { fingerprints[$0] != nil }
        guard !references.isEmpty, !targets.isEmpty else { return [:] }
        // Build a locality-sensitive index before ranking. The old implementation
        // compared every reference with every target (O(R×T)); that became the
        // dominant cost with thousands of renamed files. Image edge words are
        // stable across JPEG/PNG conversion and resizing, so shared 16-bit bands
        // provide a very cheap shortlist while still tolerating small changes.
        struct BandKey: Hashable {
            let band: Int
            let value: UInt16
        }
        struct CoarseBandKey: Hashable {
            let band: Int
            let value: UInt8
        }
        struct ColorKey: Hashable {
            let aspect: Int
            let red: UInt8
            let green: UInt8
            let blue: UInt8
        }

        var exactBuckets: [ [UInt64]: [Int] ] = [:]
        var bandBuckets: [BandKey: [Int]] = [:]
        var coarseBandBuckets: [CoarseBandKey: [Int]] = [:]
        var colorBuckets: [ColorKey: [Int]] = [:]
        for (offset, targetID) in targets.enumerated() {
            guard let fingerprint = fingerprints[targetID] else { continue }
            exactBuckets[fingerprint.edgeWords, default: []].append(offset)
            for (wordIndex, word) in fingerprint.edgeWords.enumerated() {
                // Four bands per word make the index tolerant of a few changed
                // pixels while remaining selective for large collections.
                for bandIndex in 0..<4 {
                    let shift = UInt64(48 - bandIndex * 16)
                    let value = UInt16(truncatingIfNeeded: word >> shift)
                    bandBuckets[BandKey(band: wordIndex * 4 + bandIndex, value: value), default: []].append(offset)
                    coarseBandBuckets[CoarseBandKey(
                        band: wordIndex * 4 + bandIndex,
                        value: UInt8(truncatingIfNeeded: value >> 8)
                    ), default: []].append(offset)
                }
            }
            let aspectBucket = Int((log(max(fingerprint.aspectRatio, 0.01)) * 20).rounded())
            let color = ColorKey(
                aspect: aspectBucket,
                red: fingerprint.meanRed / 16,
                green: fingerprint.meanGreen / 16,
                blue: fingerprint.meanBlue / 16
            )
            colorBuckets[color, default: []].append(offset)
        }

        func candidateOffsets(for fingerprint: ImageContentFingerprint) -> [Int] {
            if let exact = exactBuckets[fingerprint.edgeWords], !exact.isEmpty {
                return exact
            }

            var candidates = Set<Int>()
            for (wordIndex, word) in fingerprint.edgeWords.enumerated() {
                for bandIndex in 0..<4 {
                    let shift = UInt64(48 - bandIndex * 16)
                    let value = UInt16(truncatingIfNeeded: word >> shift)
                    if let bucket = bandBuckets[BandKey(band: wordIndex * 4 + bandIndex, value: value)] {
                        candidates.formUnion(bucket)
                    }
                }
            }
            if candidates.isEmpty {
                for (wordIndex, word) in fingerprint.edgeWords.enumerated() {
                    for bandIndex in 0..<4 {
                        let shift = UInt64(48 - bandIndex * 16)
                        let value = UInt8(truncatingIfNeeded: (word >> shift) >> 8)
                        if let bucket = coarseBandBuckets[CoarseBandKey(
                            band: wordIndex * 4 + bandIndex,
                            value: value
                        )] {
                            candidates.formUnion(bucket)
                        }
                    }
                }
            }
            // Flat/near-flat images can share very large edge buckets. A color
            // bucket is a better fallback in that case and keeps matching bounded.
            if candidates.isEmpty || candidates.count > 512 {
                let aspectBucket = Int((log(max(fingerprint.aspectRatio, 0.01)) * 20).rounded())
                let color = ColorKey(
                    aspect: aspectBucket,
                    red: fingerprint.meanRed / 16,
                    green: fingerprint.meanGreen / 16,
                    blue: fingerprint.meanBlue / 16
                )
                if let colorCandidates = colorBuckets[color], !colorCandidates.isEmpty {
                    candidates = Set(colorCandidates)
                }
            }
            return candidates.sorted()
        }

        // Cheap ranking only runs on indexed candidates, not the full target set.
        let ranked = references.map { referenceID in
            let reference = fingerprints[referenceID]!
            return candidateOffsets(for: reference).compactMap { offset -> (Int, Double)? in
                let targetID = targets[offset]
                let distance = fingerprints[referenceID]!.coarseDifference(from: fingerprints[targetID]!)
                return distance < 1 ? (offset, distance) : nil
            }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }.map(\.0)
        }
        var edges = Array(repeating: [(target: Int, distance: Double)](), count: references.count)
        var examined = Array(repeating: 0, count: references.count)
        var width = min(12, targets.count)
        var owner = Array(repeating: -1, count: targets.count)
        var assignment = Array(repeating: -1, count: references.count)

        while true {
            for r in references.indices {
                let end = min(width, ranked[r].count)
                for index in examined[r]..<end {
                    let t = ranked[r][index]
                    let distance = fingerprints[references[r]]!.visualDifference(from: fingerprints[targets[t]]!)
                    if distance <= maximumDifference { edges[r].append((t, distance)) }
                }
                examined[r] = end
                edges[r].sort { $0.distance == $1.distance ? $0.target < $1.target : $0.distance < $1.distance }
            }

            func augment(_ r: Int, _ visited: inout Set<Int>) -> Bool {
                // Prefer a free candidate before displacing an existing good match.
                for edge in edges[r] where owner[edge.target] == -1 {
                    owner[edge.target] = r
                    assignment[r] = edge.target
                    return true
                }
                for edge in edges[r] where visited.insert(edge.target).inserted {
                    if augment(owner[edge.target], &visited) {
                        owner[edge.target] = r
                        assignment[r] = edge.target
                        return true
                    }
                }
                return false
            }

            let order = references.indices.sorted {
                (edges[$0].first?.distance ?? 2) < (edges[$1].first?.distance ?? 2)
            }
            for r in order where assignment[r] == -1 {
                var visited: Set<Int> = []
                _ = augment(r, &visited)
            }
            if assignment.filter({ $0 >= 0 }).count == min(references.count, targets.count)
                || width >= targets.count { break }
            width = min(width * 2, targets.count)
        }
        return Dictionary(uniqueKeysWithValues: references.indices.compactMap { r in
            assignment[r] >= 0 ? (references[r], targets[assignment[r]]) : nil
        })
    }
}

public struct FileSystemImageContentFingerprintService: ImageContentFingerprinting {
    private let maximumConcurrentDecodes: Int
    private let cache: ImageContentFingerprintCache

    public init(maximumConcurrentDecodes: Int = 12) {
        self.maximumConcurrentDecodes = max(1, maximumConcurrentDecodes)
        self.cache = .shared
    }

    public func fingerprints(
        for requests: [ImageContentFingerprintRequest]
    ) async -> [UUID: ImageContentFingerprint] {
        guard !requests.isEmpty else { return [:] }

        let cached = await cache.values(for: requests)
        let cachedAssetIDs = Set(cached.keys)
        let uncachedRequests = requests.filter { !cachedAssetIDs.contains($0.assetID) }
        guard !uncachedRequests.isEmpty else { return cached }

        let decoded = await decodeFingerprints(for: uncachedRequests)
        await cache.insert(decoded, for: uncachedRequests)
        return cached.merging(decoded) { _, decoded in decoded }
    }

    private func decodeFingerprints(
        for requests: [ImageContentFingerprintRequest]
    ) async -> [UUID: ImageContentFingerprint] {
        let concurrentCount = min(maximumConcurrentDecodes, requests.count)
        return await withTaskGroup(
            of: (UUID, ImageContentFingerprint?).self,
            returning: [UUID: ImageContentFingerprint].self
        ) { group in
            var result: [UUID: ImageContentFingerprint] = [:]
            result.reserveCapacity(requests.count)
            var nextIndex = 0

            for index in 0..<concurrentCount {
                let request = requests[index]
                group.addTask {
                    guard !Task.isCancelled else { return (request.assetID, nil) }
                    return (request.assetID, await Self.makeFingerprint(for: request.fileURL))
                }
                nextIndex += 1
            }

            while let (assetID, fingerprint) = await group.next() {
                if let fingerprint {
                    result[assetID] = fingerprint
                }

                if nextIndex < requests.count {
                    let request = requests[nextIndex]
                    group.addTask {
                        guard !Task.isCancelled else { return (request.assetID, nil) }
                        return (request.assetID, await Self.makeFingerprint(for: request.fileURL))
                    }
                    nextIndex += 1
                }
            }

            return result
        }
    }

    private static func makeFingerprint(for fileURL: URL) async -> ImageContentFingerprint? {
        guard let image = await thumbnailImage(for: fileURL) else { return nil }

        let sampleSide = 16
        let bytesPerPixel = 4
        let bytesPerRow = sampleSide * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleSide * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: sampleSide,
                height: sampleSide,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide))
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide))
            return true
        }
        guard didDraw else { return nil }

        return fingerprint(from: pixels, image: image, sampleSide: sampleSide)
    }

    private static func thumbnailImage(for fileURL: URL) async -> CGImage? {
        // ImageIO is substantially cheaper than asking Quick Look to create a
        // thumbnail for every file. Use Quick Look only for formats ImageIO
        // cannot decode (for example some camera RAW variants).
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 48,
        ]
        if let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions as CFDictionary),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
            return image
        }

#if canImport(QuickLookThumbnailing)
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: 48, height: 48),
            scale: 1,
            representationTypes: .thumbnail
        )
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return representation.cgImage
        }
#endif
        return nil
    }

    private static func fingerprint(
        from pixels: [UInt8],
        image: CGImage,
        sampleSide: Int
    ) -> ImageContentFingerprint {
        let bytesPerPixel = 4
        var luminance: [UInt8] = []
        luminance.reserveCapacity(sampleSide * sampleSide)
        var chrominance: [UInt8] = []
        chrominance.reserveCapacity(sampleSide * sampleSide * 2)
        var redTotal = 0
        var greenTotal = 0
        var blueTotal = 0

        for pixelIndex in 0..<(sampleSide * sampleSide) {
            let byteIndex = pixelIndex * bytesPerPixel
            let red = Int(pixels[byteIndex])
            let green = Int(pixels[byteIndex + 1])
            let blue = Int(pixels[byteIndex + 2])
            redTotal += red
            greenTotal += green
            blueTotal += blue
            luminance.append(UInt8((red * 77 + green * 150 + blue * 29) >> 8))
            chrominance.append(UInt8(clamping: (red - green + 255) / 2))
            chrominance.append(UInt8(clamping: (blue - green + 255) / 2))
        }

        let sampleCount = luminance.count
        let mean = Double(luminance.reduce(0) { $0 + Int($1) }) / Double(sampleCount)
        let variance = luminance.reduce(0.0) { result, value in
            let delta = Double(value) - mean
            return result + delta * delta
        } / Double(sampleCount)
        let deviation = sqrt(variance)
        let normalizationScale = max(deviation, 16)
        let normalized = luminance.map { value -> UInt8 in
            let scaled = 128 + (Double(value) - mean) * 40 / normalizationScale
            return UInt8(clamping: Int(scaled.rounded()))
        }

        var edgeWords = [UInt64](repeating: 0, count: 8)
        var bitIndex = 0
        func appendEdgeBit(_ isAscending: Bool) {
            if isAscending {
                edgeWords[bitIndex / 64] |= UInt64(1) << UInt64(bitIndex % 64)
            }
            bitIndex += 1
        }

        for y in 0..<sampleSide {
            for x in 0..<(sampleSide - 1) {
                let current = normalized[y * sampleSide + x]
                let next = normalized[y * sampleSide + x + 1]
                appendEdgeBit(next >= current)
            }
        }
        for y in 0..<(sampleSide - 1) {
            for x in 0..<sampleSide {
                let current = normalized[y * sampleSide + x]
                let next = normalized[(y + 1) * sampleSide + x]
                appendEdgeBit(next >= current)
            }
        }

        return ImageContentFingerprint(
            edgeWords: edgeWords,
            normalizedLuminance: normalized,
            meanRed: UInt8(clamping: redTotal / sampleCount),
            meanGreen: UInt8(clamping: greenTotal / sampleCount),
            meanBlue: UInt8(clamping: blueTotal / sampleCount),
            luminanceDeviation: UInt8(clamping: Int(deviation.rounded())),
            aspectRatio: Double(image.width) / Double(max(image.height, 1)),
            chrominance: chrominance
        )
    }
}

private struct ImageContentFingerprintCacheKey: Hashable, Sendable {
    let path: String
    let fileSizeBytes: Int64
    let modificationMilliseconds: Int64

    init(_ request: ImageContentFingerprintRequest) {
        path = request.fileURL.path
        fileSizeBytes = request.fileSizeBytes
        modificationMilliseconds = Int64(
            (request.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0) * 1_000
        )
    }
}

private actor ImageContentFingerprintCache {
    static let shared = ImageContentFingerprintCache()
    private struct QueueEntry {
        let key: ImageContentFingerprintCacheKey
        let generation: UInt64
    }

    private var storage: [ImageContentFingerprintCacheKey: ImageContentFingerprint] = [:]
    private var accessOrder: [QueueEntry] = []
    private var accessHead = 0
    private var generations: [ImageContentFingerprintCacheKey: UInt64] = [:]
    private var nextGeneration: UInt64 = 0

    func values(
        for requests: [ImageContentFingerprintRequest]
    ) -> [UUID: ImageContentFingerprint] {
        requests.reduce(into: [UUID: ImageContentFingerprint]()) { result, request in
            if let fingerprint = storage[ImageContentFingerprintCacheKey(request)] {
                result[request.assetID] = fingerprint
            }
        }
    }

    func insert(
        _ fingerprints: [UUID: ImageContentFingerprint],
        for requests: [ImageContentFingerprintRequest]
    ) {
        for request in requests {
            guard let fingerprint = fingerprints[request.assetID] else { continue }
            let key = ImageContentFingerprintCacheKey(request)
            storage[key] = fingerprint
            nextGeneration &+= 1
            generations[key] = nextGeneration
            accessOrder.append(QueueEntry(key: key, generation: nextGeneration))
        }
        while storage.count > 12_000, accessHead < accessOrder.count {
            let entry = accessOrder[accessHead]
            accessHead += 1
            // A key may have been refreshed since this queue entry was added.
            // Only the newest entry is allowed to evict its value.
            guard generations[entry.key] == entry.generation else { continue }
            storage.removeValue(forKey: entry.key)
            generations.removeValue(forKey: entry.key)
        }
        // Compact occasionally, instead of removeFirst() on every eviction.
        if accessHead > 4096 && accessHead * 2 > accessOrder.count {
            accessOrder.removeFirst(accessHead)
            accessHead = 0
        }
    }
}
