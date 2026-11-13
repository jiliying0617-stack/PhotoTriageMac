import Foundation

/// Shared by filename pairing and the visual-matching planner. No file I/O is needed.
public enum FilenameMatchingService {
    public static func match(
        referenceRows: [[AssetRecord]],
        targets: [AssetRecord],
        useRelativePath: Bool = false
    ) -> [Int: AssetRecord] {
        func keyVariants(_ asset: AssetRecord) -> [String] {
            useRelativePath
                ? AssetRecord.comparisonRelativePathKeys(for: asset.relativePath)
                : AssetRecord.comparisonFilenameKeys(for: asset.filename)
        }

        var matches: [Int: AssetRecord] = [:]
        var usedIDs: Set<UUID> = []
        // Reserve all exact names before any suffix-equivalent name can consume them.
        // Cursor queues avoid repeated removeFirst() copies for large duplicate sets.
        // A source name can already contain a sequence: 634_0 -> 634_0_2.
        // Prefer that direct parent relationship over grouping sibling suffixes.
        // Match exact stems first, then progressively relaxed aliases. This is
        // important for exporters that append more than one sequence suffix
        // (`name_1_2`) or use a short marker (`name_k_2`). A target appears in
        // every alias bucket, but `usedIDs` guarantees it can only be consumed
        // once. The pass order keeps exact names globally reserved.
        let variants = targets.map { ($0, keyVariants($0)) }
        let referenceVariants = referenceRows.map { $0.map(keyVariants) }
        let maxTargetDepth = variants.map { $0.1.count }.max() ?? 1
        let maxReferenceDepth = referenceVariants.flatMap { $0 }.map(\.count).max() ?? 1
        // Exact names always win. Then allow one side to be an arbitrary
        // export alias (`base` ↔ `base_k_2`). Finally compare the first alias
        // level on both sides. Deeper-to-deeper matching is intentionally
        // avoided: `634_0_2` and `634_1_1` both collapse to `634`, but they are
        // distinct numbered assets and must not be falsely paired.
        var passes: [(Int, Int)] = [(0, 0)]
        if maxTargetDepth > 1 { passes.append(contentsOf: (1..<maxTargetDepth).map { (0, $0) }) }
        if maxReferenceDepth > 1 { passes.append(contentsOf: (1..<maxReferenceDepth).map { ($0, 0) }) }
        passes.append((1, 1))
        for (referenceDepth, targetDepth) in passes {
            if matches.count == referenceRows.count || usedIDs.count == targets.count { break }
            var buckets: [String: [AssetRecord]] = [:]
            for (target, aliases) in variants {
                let key = aliases[min(targetDepth, aliases.count - 1)]
                buckets[key, default: []].append(target)
            }
            var cursors: [String: Int] = [:]
            for (rowIndex, references) in referenceVariants.enumerated() where matches[rowIndex] == nil {
                for aliases in references {
                    let key = aliases[min(referenceDepth, aliases.count - 1)]
                    guard let candidates = buckets[key] else { continue }
                    var cursor = cursors[key, default: 0]
                    while cursor < candidates.count, usedIDs.contains(candidates[cursor].id) {
                        cursor += 1
                    }
                    cursors[key] = cursor
                    guard cursor < candidates.count else { continue }
                    let match = candidates[cursor]
                    cursors[key] = cursor + 1
                    matches[rowIndex] = match
                    usedIDs.insert(match.id)
                    break
                }
            }
        }
        return matches
    }
}

/// Compute the normalized keys once per asset, not in every sorting comparison.
struct AssetFilenameSortKey {
    let name: String
    let path: String
    let sequence: Int?
    let originalName: String
    let originalPath: String

    init(_ asset: AssetRecord) {
        name = AssetRecord.comparisonFilenameKey(for: asset.filename)
        path = AssetRecord.comparisonRelativePathKey(for: asset.relativePath)
        sequence = AssetRecord.comparisonFilenameSequence(for: asset.filename)
        originalName = asset.filename
        originalPath = asset.relativePath
    }

    func compare(to other: Self, pathFirst: Bool = false) -> ComparisonResult {
        let primary = pathFirst ? path.localizedStandardCompare(other.path) : name.localizedStandardCompare(other.name)
        if primary != .orderedSame { return primary }
        // Keep the base file at the anchor position, followed by `_1`, `_2`,
        // `_3` in numeric order. Comparing raw names here makes localized
        // sorting place suffixed exports before/after the whole group.
        switch (sequence, other.sequence) {
        case let (lhs?, rhs?):
            if lhs != rhs { return lhs < rhs ? .orderedAscending : .orderedDescending }
        case (nil, .some):
            return .orderedAscending
        case (.some, nil):
            return .orderedDescending
        case (nil, nil):
            break
        }
        let secondary = originalName.localizedStandardCompare(other.originalName)
        if secondary != .orderedSame { return secondary }
        return originalPath.localizedStandardCompare(other.originalPath)
    }

    static func sorted(_ assets: [AssetRecord], pathFirst: Bool = false) -> [AssetRecord] {
        assets.enumerated().map { (asset: $0.element, key: Self($0.element), offset: $0.offset) }
            .sorted {
                let order = $0.key.compare(to: $1.key, pathFirst: pathFirst)
                return order == .orderedSame ? $0.offset < $1.offset : order == .orderedAscending
            }.map(\.asset)
    }
}
