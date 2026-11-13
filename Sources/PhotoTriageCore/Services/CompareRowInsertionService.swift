import Foundation

/// Merge unmatched files without scanning/copying the whole matrix for each file.
/// Existing rows (including content matches and missing slots) retain their order.
enum CompareRowInsertionService {
    private struct Anchor {
        let key: AssetFilenameSortKey
        let row: Int
    }

    private struct AnchorIndex {
        let anchors: [Anchor]
        let firstRowAfter: [Int]
        let lastRow: Int

        init(_ values: [Anchor]) {
            anchors = values.sorted { $0.key.compare(to: $1.key) == .orderedAscending }
            lastRow = values.map(\.row).max() ?? -1
            var minima = Array(repeating: Int.max, count: values.count)
            var minimum = Int.max
            for index in anchors.indices.reversed() {
                minimum = min(minimum, anchors[index].row)
                minima[index] = minimum
            }
            firstRowAfter = minima
        }

        func insertionBefore(_ key: AssetFilenameSortKey) -> Int? {
            var lower = 0
            var upper = anchors.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if key.compare(to: anchors[middle].key) == .orderedAscending {
                    upper = middle
                } else {
                    lower = middle + 1
                }
            }
            return lower < anchors.count ? firstRowAfter[lower] : nil
        }
    }

    private struct InsertionBucket {
        var followingGroups: [[AssetRecord]] = []
        var lastFollowingStem: String?
        var preceding: [AssetRecord] = []

        mutating func add(_ asset: AssetRecord, stem: String, followsAnchor: Bool) {
            if followsAnchor {
                if lastFollowingStem == stem {
                    followingGroups[followingGroups.count - 1].append(asset)
                } else {
                    followingGroups.append([asset])
                    lastFollowingStem = stem
                }
            } else {
                preceding.append(asset)
            }
        }
    }

    static func inserting(
        _ targets: [AssetRecord], into rows: [[AssetRecord?]], column: Int, columnCount: Int
    ) -> [[AssetRecord?]] {
        guard !targets.isEmpty else { return rows }
        var anchorsByStem: [String: [Anchor]] = [:]
        var primaryAnchors: [Anchor] = []
        for (index, row) in rows.enumerated() {
            var seenStems: Set<String> = []
            for asset in row.compactMap(\.self) {
                let key = AssetFilenameSortKey(asset)
                if seenStems.isEmpty { primaryAnchors.append(Anchor(key: key, row: index)) }
                if seenStems.insert(key.name).inserted {
                    anchorsByStem[key.name, default: []].append(Anchor(key: key, row: index))
                }
            }
        }
        let stemIndexes = anchorsByStem.mapValues(AnchorIndex.init)
        let fallbackIndex = AnchorIndex(primaryAnchors)
        var insertions: [Int: InsertionBucket] = [:]
        for asset in AssetFilenameSortKey.sorted(targets) {
            let key = AssetFilenameSortKey(asset)
            let boundary: Int
            let followsAnchor: Bool
            if let index = stemIndexes[key.name] {
                if let before = index.insertionBefore(key) {
                    boundary = before
                    followsAnchor = false
                } else {
                    boundary = index.lastRow + 1
                    followsAnchor = true
                }
            } else {
                boundary = fallbackIndex.insertionBefore(key) ?? rows.count
                followsAnchor = false
            }
            insertions[boundary, default: InsertionBucket()].add(
                asset, stem: key.name, followsAnchor: followsAnchor
            )
        }

        var result: [[AssetRecord?]] = []
        result.reserveCapacity(rows.count + targets.count)
        for boundary in 0...rows.count {
            if let bucket = insertions[boundary] {
                // A shared boundary can follow B and precede A in added-date
                // order: keep B's new versions next to B, before A's versions.
                // When renamed/content-matched stems share the previous row,
                // later stem groups go directly after it, as in serial insertion.
                for group in bucket.followingGroups.reversed() {
                    for asset in group {
                        var row = [AssetRecord?](repeating: nil, count: columnCount)
                        row[column] = asset
                        result.append(row)
                    }
                }
                for asset in bucket.preceding {
                    var row = [AssetRecord?](repeating: nil, count: columnCount)
                    row[column] = asset
                    result.append(row)
                }
            }
            if boundary < rows.count { result.append(rows[boundary]) }
        }
        return result
    }
}
