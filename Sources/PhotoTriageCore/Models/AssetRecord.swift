import Foundation

public struct AssetRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var libraryID: UUID
    public var filename: String
    public var filenameKey: String
    public var relativePath: String
    public var format: AssetFormat
    public var fileSizeBytes: Int64
    public var width: Int
    public var height: Int
    public var ratingState: RatingState
    public var appTags: [AppTag]
    public var finderTags: [FinderTag]
    /// Non-nil when these effective tags are saved locally, not confirmed in Finder.
    public var finderTagSyncIssue: String?
    public var isRaw: Bool
    public var rotationDegrees: Int
    public var addedToDirectoryDate: Date?
    public var contentModificationDate: Date?

    public init(
        id: UUID = UUID(),
        libraryID: UUID,
        filename: String,
        relativePath: String,
        format: AssetFormat,
        fileSizeBytes: Int64,
        width: Int,
        height: Int,
        ratingState: RatingState = .pending,
        appTags: [AppTag] = [],
        finderTags: [FinderTag] = [],
        finderTagSyncIssue: String? = nil,
        isRaw: Bool = false,
        rotationDegrees: Int = 0,
        addedToDirectoryDate: Date? = nil,
        contentModificationDate: Date? = nil
    ) {
        self.id = id
        self.libraryID = libraryID
        self.filename = filename
        self.filenameKey = Self.filenameKey(for: filename)
        self.relativePath = relativePath
        self.format = format
        self.fileSizeBytes = fileSizeBytes
        self.width = width
        self.height = height
        self.ratingState = ratingState
        self.appTags = appTags
        self.finderTags = finderTags
        self.finderTagSyncIssue = finderTagSyncIssue
        self.isRaw = isRaw
        self.rotationDegrees = Self.normalizedRotationDegrees(rotationDegrees)
        self.addedToDirectoryDate = addedToDirectoryDate
        self.contentModificationDate = contentModificationDate
    }

    public var hasKnownDimensions: Bool {
        width > 0 && height > 0
    }

    public var dimensionDescription: String {
        hasKnownDimensions ? "\(width)×\(height)" : "待读取"
    }

    public var normalizedRotationDegrees: Int {
        Self.normalizedRotationDegrees(rotationDegrees)
    }

    public var priorityTag: PriorityTag? {
        appTags.compactMap(PriorityTag.fromAppTag).first
    }

    public static func normalizedRotationDegrees(_ degrees: Int) -> Int {
        let normalized = degrees % 360
        return normalized >= 0 ? normalized : normalized + 360
    }

    public static func filenameKey(for filename: String) -> String {
        let basename = NSString(string: filename).deletingPathExtension
        return (basename.isEmpty ? filename : basename).lowercased()
    }

    /// Comparison-only key: normalizes Unicode spelling and invisible edge
    /// whitespace without changing the stored filename/review identity.
    public static func matchingFilenameKey(for filename: String) -> String {
        let basename = NSString(string: filename).deletingPathExtension
        let value = basename.isEmpty ? filename : basename
        return value.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    public static func relativePathKey(for relativePath: String) -> String {
        let basenamePath = NSString(string: relativePath).deletingPathExtension
        return (basenamePath.isEmpty ? relativePath : basenamePath).lowercased()
    }

    public static func matchingRelativePathKey(for relativePath: String) -> String {
        let path = NSString(string: relativePath)
        let folder = path.deletingLastPathComponent
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let name = matchingFilenameKey(for: path.lastPathComponent)
        return folder.isEmpty ? name : folder + "/" + name
    }

    /// Export/copy sequence suffixes are ignored only for comparison and ordering.
    /// Keep filenameKey unchanged: it is also used by review-state tracking.
    public static func comparisonFilenameKey(for filename: String) -> String {
        let stem = matchingFilenameKey(for: filename)
        guard let separator = stem.lastIndex(of: "_"), separator != stem.startIndex else { return stem }
        let suffix = stem[stem.index(after: separator)...]
        guard (1...2).contains(suffix.utf8.count),
              suffix.utf8.allSatisfy({ (48...57).contains($0) }) else { return stem }
        return String(stem[..<separator])
    }

    /// Returns the trailing export sequence used for filename ordering.
    /// A missing suffix is ordered before `_1`, `_2`, etc. The value is kept
    /// separate from the comparison key so variants stay next to their base
    /// file instead of being sorted by the raw localized filename.
    public static func comparisonFilenameSequence(for filename: String) -> Int? {
        let stem = matchingFilenameKey(for: filename)
        guard let separator = stem.lastIndex(of: "_"), separator != stem.startIndex else { return nil }
        let suffix = stem[stem.index(after: separator)...]
        guard (1...2).contains(suffix.utf8.count),
              suffix.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(suffix)
    }

    public static func comparisonFilenameKeys(for filename: String) -> [String] {
        var keys = [matchingFilenameKey(for: filename)]
        while let previous = keys.last,
              let separator = previous.lastIndex(of: "_"), separator != previous.startIndex {
            let suffix = previous[previous.index(after: separator)...]
            let isShortNumeric = (1...2).contains(suffix.utf8.count)
                && suffix.utf8.allSatisfy { (48...57).contains($0) }
            guard isShortNumeric else { break }
            let relaxed = String(previous[..<separator])
            guard relaxed != previous else { break }
            keys.append(relaxed)
        }
        return keys
    }

    public static func comparisonRelativePathKey(for relativePath: String) -> String {
        comparisonRelativePathKeys(for: relativePath).dropFirst().first ?? matchingRelativePathKey(for: relativePath)
    }

    public static func comparisonRelativePathKeys(for relativePath: String) -> [String] {
        let path = NSString(string: relativePath)
        let folder = path.deletingLastPathComponent
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let names = comparisonFilenameKeys(for: path.lastPathComponent)
        return names.map { name in
            folder.isEmpty ? name : folder.lowercased() + "/" + name
        }
    }

    public var compareAlignmentKey: String {
        filenameKey
    }

    public var compareRelativeAlignmentKey: String {
        Self.relativePathKey(for: relativePath)
    }
}
