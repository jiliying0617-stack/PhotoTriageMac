import Foundation
#if canImport(AppKit)
import AppKit
import ImageIO

enum PhotoImagePipeline {
    static func cachedImage(for fileURL: URL, maxPixelSize: CGFloat) -> NSImage? {
        let requestedMaxPixelSize = normalizedMaxPixelSize(maxPixelSize)
        let key = cacheKey(for: fileURL, maxPixelSize: requestedMaxPixelSize)
        return PhotoImageCache.shared.image(for: key)
    }

    static func cachedPreviewImage(for fileURL: URL) -> NSImage? {
        PhotoImageCache.shared.previewImage(for: versionKey(for: fileURL))
    }

    // Browser/compare views already have scan metadata. Do not synchronously
    // stat a network file on the main thread just to look up an in-memory frame.
    static func cachedImage(
        for fileURL: URL, maxPixelSize: CGFloat, fileSizeBytes: Int64, modificationDate: Date?
    ) -> NSImage? {
        guard let modificationDate else { return nil }
        let version = versionKey(for: fileURL, fileSizeBytes: fileSizeBytes, modificationDate: modificationDate)
        return PhotoImageCache.shared.image(for: "\(version)#\(Int(normalizedMaxPixelSize(maxPixelSize)))")
    }

    static func cachedPreviewImage(
        for fileURL: URL, fileSizeBytes: Int64, modificationDate: Date?
    ) -> NSImage? {
        guard let modificationDate else { return nil }
        return PhotoImageCache.shared.previewImage(
            for: versionKey(for: fileURL, fileSizeBytes: fileSizeBytes, modificationDate: modificationDate)
        )
    }

    static func image(
        for fileURL: URL,
        maxPixelSize: CGFloat,
        cachePolicy: PhotoImageCachePolicy = .readWrite,
        shouldContinue: @Sendable () -> Bool = { true }
    ) -> NSImage? {
        guard shouldContinue() else { return nil }
        let requestedMaxPixelSize = normalizedMaxPixelSize(maxPixelSize)
        let previewKey = versionKey(for: fileURL)
        let key = "\(previewKey)#\(Int(requestedMaxPixelSize.rounded()))"

        if cachePolicy.canRead,
           let cachedImage = PhotoImageCache.shared.image(for: key) {
            return cachedImage
        }

        let image = renderImage(for: fileURL, maxPixelSize: requestedMaxPixelSize)
        guard shouldContinue(), previewKey == versionKey(for: fileURL), shouldContinue() else { return nil }

        if cachePolicy.canWrite, let image {
            PhotoImageCache.shared.insert(image, for: key, previewKey: previewKey)
        }

        return image
    }

    static func loadImage(for fileURL: URL, maxPixelSize: CGFloat, cachePolicy: PhotoImageCachePolicy = .readWrite) async -> NSImage? {
        await PhotoImageDecodeLimiter.shared.run { shouldContinue in
            image(for: fileURL, maxPixelSize: maxPixelSize, cachePolicy: cachePolicy,
                  shouldContinue: shouldContinue)
        }
    }

    static func thumbnail(for fileURL: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let cgImage = cgThumbnail(for: fileURL, maxPixelSize: normalizedMaxPixelSize(maxPixelSize)) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    static func cgImage(for fileURL: URL, maxPixelSize: CGFloat) -> CGImage? {
        cgThumbnail(for: fileURL, maxPixelSize: normalizedMaxPixelSize(maxPixelSize))
    }

    static func fullResolutionCGImage(for fileURL: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let pixelSize = imagePixelSize(from: source)
        let maxPixelSize = max(pixelSize.width, pixelSize.height)
        guard maxPixelSize > 0 else {
            return CGImageSourceCreateImageAtIndex(source, 0, sourceOptions as CFDictionary)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded(.up))
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }

    static func pixelSize(for fileURL: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let size = imagePixelSize(from: source)
        return size.width > 0 && size.height > 0 ? size : nil
    }

    static func cacheKey(for fileURL: URL, maxPixelSize: CGFloat) -> String {
        let normalizedSize = Int(normalizedMaxPixelSize(maxPixelSize).rounded())
        return "\(versionKey(for: fileURL))#\(normalizedSize)"
    }

    private static func versionKey(for fileURL: URL) -> String {
        "\(fileURL.path)#\(fileSignature(for: fileURL))"
    }

    private static func versionKey(for fileURL: URL, fileSizeBytes: Int64, modificationDate: Date) -> String {
        "\(fileURL.path)#\(modificationDate.timeIntervalSinceReferenceDate)#\(fileSizeBytes)"
    }

    static func fileSignature(for fileURL: URL?) -> String {
        guard let fileURL else { return "missing" }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        var freshURL = fileURL
        freshURL.removeAllCachedResourceValues()
        let values = try? freshURL.resourceValues(forKeys: keys)
        let modifiedAt = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        let fileSize = values?.fileSize ?? 0
        return "\(modifiedAt)#\(fileSize)"
    }

    static func clearCache() {
        PhotoImageCache.shared.clear()
    }

    private static func renderImage(for fileURL: URL, maxPixelSize: CGFloat) -> NSImage? {
        if let cgImage = cgThumbnail(for: fileURL, maxPixelSize: maxPixelSize) {
            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
        }

        return NSImage(contentsOf: fileURL)
    }

    private static func cgThumbnail(for fileURL: URL, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded())
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }

    private static var sourceOptions: [CFString: Any] {
        [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: true
        ]
    }

    private static func imagePixelSize(from source: CGImageSource) -> CGSize {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .zero
        }

        let width = CGFloat((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0)
        let height = CGFloat((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0)
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1

        if [5, 6, 7, 8].contains(orientation) {
            return CGSize(width: height, height: width)
        }

        return CGSize(width: width, height: height)
    }

    private static func normalizedMaxPixelSize(_ maxPixelSize: CGFloat) -> CGFloat {
        guard maxPixelSize.isFinite else { return 1 }
        return min(CGFloat(Int32.max), max(1, maxPixelSize.rounded()))
    }
}

enum PhotoImageCachePolicy {
    case bypass
    case refresh
    case readWrite

    var canRead: Bool {
        switch self {
        case .bypass, .refresh:
            return false
        case .readWrite:
            return true
        }
    }

    var canWrite: Bool {
        switch self {
        case .bypass:
            return false
        case .refresh, .readWrite:
            return true
        }
    }
}

final class PhotoImageCache: @unchecked Sendable {
    static let shared = PhotoImageCache(monitorsMemoryPressure: true)
    private let lock = NSLock()
    private let totalCostLimit: Int
    private let countLimit: Int
    private var entries: [String: Entry] = [:]
    private var previewKeys: [String: Set<String>] = [:]
    private var newest: Entry?
    private var oldest: Entry?
    private var retainedCost = 0
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    // One strict budget for images and previews. A second owning preview cache
    // kept full-resolution frames alive after the primary cache evicted them.
    init(totalCostLimit: Int = 384 * 1024 * 1024, countLimit: Int = 900,
         monitorsMemoryPressure: Bool = false) {
        self.totalCostLimit = max(0, totalCostLimit)
        self.countLimit = max(1, countLimit)
        if monitorsMemoryPressure {
            let source = DispatchSource.makeMemoryPressureSource(
                eventMask: [.warning, .critical], queue: .global(qos: .utility)
            )
            source.setEventHandler { [weak self] in self?.clear() }
            memoryPressureSource = source
            source.activate()
        }
    }

    deinit { memoryPressureSource?.cancel() }

    var totalCost: Int {
        lock.lock()
        defer { lock.unlock() }
        return retainedCost
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func image(for key: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        promote(entry)
        return entry.image
    }

    func previewImage(for key: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = previewKeys[key]?.compactMap({ entries[$0] })
            .max(by: { $0.maxPixelDimension < $1.maxPixelDimension }) else { return nil }
        promote(entry)
        return entry.image
    }

    func insert(_ image: NSImage, for key: String, previewKey: String) {
        let cost = estimatedCost(for: image)
        lock.lock()
        defer { lock.unlock() }
        if let previous = entries[key] { remove(previous) }
        // A huge original is still returned to the viewer at full quality, but
        // does not become an unbounded long-lived cache entry.
        guard cost <= totalCostLimit else { return }
        while (retainedCost > totalCostLimit - cost || entries.count >= countLimit), let oldest {
            remove(oldest)
        }
        let entry = Entry(key: key, previewKey: previewKey, image: image, cost: cost)
        entries[key] = entry
        previewKeys[previewKey, default: []].insert(key)
        retainedCost += cost
        promote(entry)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        newest = nil
        oldest = nil
        entries.removeAll(keepingCapacity: false)
        previewKeys.removeAll(keepingCapacity: false)
        retainedCost = 0
    }

    private func promote(_ entry: Entry) {
        guard newest !== entry else { return }
        if oldest === entry { oldest = entry.next }
        entry.previous?.next = entry.next
        entry.next?.previous = entry.previous
        entry.previous = newest
        entry.next = nil
        newest?.next = entry
        newest = entry
        if oldest == nil { oldest = entry }
    }

    private func remove(_ entry: Entry) {
        if newest === entry { newest = entry.previous }
        if oldest === entry { oldest = entry.next }
        entry.previous?.next = entry.next
        entry.next?.previous = entry.previous
        entry.previous = nil
        entry.next = nil
        entries[entry.key] = nil
        retainedCost -= entry.cost
        previewKeys[entry.previewKey]?.remove(entry.key)
        if previewKeys[entry.previewKey]?.isEmpty == true { previewKeys[entry.previewKey] = nil }
    }

    private func estimatedCost(for image: NSImage) -> Int {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let (cost, overflow) = cgImage.bytesPerRow.multipliedReportingOverflow(by: cgImage.height)
            return overflow ? Int.max : max(1, cost)
        }
        let cost = image.size.width * image.size.height * 4
        guard cost.isFinite, cost < CGFloat(Int.max) else { return Int.max }
        return max(1, Int(cost))
    }

    private final class Entry {
        let key: String
        let previewKey: String
        let image: NSImage
        let cost: Int
        let maxPixelDimension: CGFloat
        weak var previous: Entry?
        var next: Entry?

        init(key: String, previewKey: String, image: NSImage, cost: Int) {
            self.key = key
            self.previewKey = previewKey
            self.image = image
            self.cost = cost
            maxPixelDimension = max(image.size.width, image.size.height)
        }
    }
}
#endif
