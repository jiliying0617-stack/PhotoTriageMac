import Foundation

public enum CompareGroupingService {
    public static func buildGroups(
        libraries: [LibraryFolder],
        assets: [AssetRecord]
    ) -> [CompareGroup] {
        let sortedLibraries = libraries.sorted { $0.columnIndex < $1.columnIndex }
        let assetsByLibrary = Dictionary(grouping: assets, by: \.libraryID)
        var rows: [[AssetRecord?]] = []
        for (column, library) in sortedLibraries.enumerated() {
            let targets = AssetFilenameSortKey.sorted(assetsByLibrary[library.id, default: []], pathFirst: true)
            let matches = FilenameMatchingService.match(
                referenceRows: rows.map { $0.compactMap(\.self) }, targets: targets, useRelativePath: true
            )
            for (rowIndex, asset) in matches { rows[rowIndex][column] = asset }
            let usedIDs = Set(matches.values.map(\.id))
            for asset in targets where !usedIDs.contains(asset.id) {
                var row = [AssetRecord?](repeating: nil, count: sortedLibraries.count)
                row[column] = asset
                rows.append(row)
            }
        }

        let orderedRows = rows.compactMap { row -> (slots: [AssetRecord?], asset: AssetRecord, key: AssetFilenameSortKey)? in
            guard let asset = row.compactMap(\.self).first else { return nil }
            return (row, asset, AssetFilenameSortKey(asset))
        }.sorted { $0.key.compare(to: $1.key, pathFirst: true) == .orderedAscending }
        // Keep every variant, including duplicate stems with different extensions.
        // Existing unique group IDs stay unchanged; collisions get an asset identity.
        var usedGroupKeys: Set<String> = []
        return orderedRows.map { row in
            let path = row.asset.compareRelativeAlignmentKey
            let uniquePath = usedGroupKeys.insert(path).inserted ? path : path + "#" + row.asset.id.uuidString
            return CompareGroup(
                filenameKey: row.asset.filenameKey,
                relativePath: uniquePath,
                displayName: row.asset.filename,
                slots: zip(sortedLibraries, row.slots).map { CompareSlot(library: $0, asset: $1) }
            )
        }
    }
}
