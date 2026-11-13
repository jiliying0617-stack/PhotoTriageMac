import Foundation

public struct VisibleAssetQuery: Equatable, Sendable {
    public var searchText: String
    public var selectedLibraryID: UUID?
    public var selectedFolderPath: String?
    public var selectedFolderPaths: Set<String>
    public var selectedFolderOrder: [String]
    public var showUnreviewedOnly: Bool
    public var viewedCompareGroupKeys: Set<String>
    public var categoryFilter: AssetCategoryFilter
    public var sortMode: AssetSortMode
    public var pinnedAssetIDs: Set<UUID>
    public var priorityTagNames: [PriorityTag: String]

    public init(
        searchText: String = "",
        selectedLibraryID: UUID? = nil,
        selectedFolderPath: String? = nil,
        selectedFolderPaths: Set<String> = [],
        selectedFolderOrder: [String] = [],
        showUnreviewedOnly: Bool = false,
        viewedCompareGroupKeys: Set<String> = [],
        categoryFilter: AssetCategoryFilter = .all,
        sortMode: AssetSortMode = .filename,
        pinnedAssetIDs: Set<UUID> = [],
        priorityTagNames: [PriorityTag: String] = [:]
    ) {
        self.searchText = searchText
        self.selectedLibraryID = selectedLibraryID
        self.selectedFolderPath = selectedFolderPath
        self.selectedFolderPaths = selectedFolderPaths
        self.selectedFolderOrder = selectedFolderOrder
        self.showUnreviewedOnly = showUnreviewedOnly
        self.viewedCompareGroupKeys = viewedCompareGroupKeys
        self.categoryFilter = categoryFilter
        self.sortMode = sortMode
        self.pinnedAssetIDs = pinnedAssetIDs
        self.priorityTagNames = priorityTagNames
    }
}

public struct VisibleAssetSnapshot: Equatable, Sendable {
    public var query: VisibleAssetQuery
    /// Assets matching the current library/folder/search scope before category filtering.
    /// This lets scope-level diagnostics (such as missing-image detection) remain stable
    /// when the user switches between Keep/Reject/Pending category filters.
    public var scopedAssets: [AssetRecord]
    public var assets: [AssetRecord]
    public var assetIDs: [UUID]
    public var assetIDSet: Set<UUID>
    private var positionByID: [UUID: Int]
    /// Category changes only filter this order; tagging never re-sorts filenames.
    private var orderedScopedAssets: [AssetRecord]
    public var keepCount: Int
    public var rejectCount: Int
    public var pendingCount: Int
    public var categorySummary: AssetCategorySummary
    public var basenameCompareGroups: [[AssetRecord]]

    public init(
        query: VisibleAssetQuery = VisibleAssetQuery(),
        assets: [AssetRecord] = [],
        includeBasenameCompareGroups: Bool = true
    ) {
        self.query = query

        let trimmedSearch = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedFolders = query.selectedFolderPaths.isEmpty
            ? Set(query.selectedFolderPath.map { [$0] } ?? [])
            : query.selectedFolderPaths

        var scopedAssets: [AssetRecord] = []
        scopedAssets.reserveCapacity(assets.count)
        var scopedKeepCount = 0
        var scopedRejectCount = 0
        var scopedPendingCount = 0
        var prioritySummary = PriorityTagSummary()

        for asset in assets {
            let matchesSearch = trimmedSearch.isEmpty
                || asset.filename.localizedCaseInsensitiveContains(trimmedSearch)
                || asset.relativePath.localizedCaseInsensitiveContains(trimmedSearch)
                || asset.appTags.contains { $0.name.localizedCaseInsensitiveContains(trimmedSearch) }
                || asset.priorityTag.flatMap { query.priorityTagNames[$0] }?.localizedCaseInsensitiveContains(trimmedSearch) == true
                || asset.finderTags.contains { $0.name.localizedCaseInsensitiveContains(trimmedSearch) }

            let matchesLibrary = query.selectedLibraryID == nil || query.selectedLibraryID == asset.libraryID
            let matchesFolder = selectedFolders.isEmpty || selectedFolders.contains { folderPath in
                asset.relativePath == folderPath || asset.relativePath.hasPrefix(folderPath + "/")
            }
            let matchesReview = !query.showUnreviewedOnly || !query.viewedCompareGroupKeys.contains(asset.filenameKey)

            guard matchesSearch && matchesLibrary && matchesFolder && matchesReview else { continue }
            scopedAssets.append(asset)

            switch asset.ratingState {
            case .keep: scopedKeepCount += 1
            case .reject: scopedRejectCount += 1
            case .pending: scopedPendingCount += 1
            }
            prioritySummary.record(asset.priorityTag)
        }

        self.scopedAssets = scopedAssets
        self.categorySummary = AssetCategorySummary(
            totalCount: scopedAssets.count,
            keepCount: scopedKeepCount,
            rejectCount: scopedRejectCount,
            pendingCount: scopedPendingCount,
            priorityTagSummary: prioritySummary,
            finderTagColorSummary: FinderTagColorSummary(assets: scopedAssets)
        )

        let orderedScopedAssets = Self.orderAssetsBySelectedFolders(
            scopedAssets, selectedFolderOrder: query.selectedFolderOrder, sortMode: query.sortMode
        )
        self.orderedScopedAssets = orderedScopedAssets
        var visibleAssets: [AssetRecord] = []
        visibleAssets.reserveCapacity(scopedAssets.count)
        for asset in orderedScopedAssets {
            if query.pinnedAssetIDs.contains(asset.id) {
                visibleAssets.append(asset)
                continue
            }

            switch query.categoryFilter {
            case .all:
                visibleAssets.append(asset)
            case .rating(let rating):
                if asset.ratingState == rating { visibleAssets.append(asset) }
            case .priority(let priorityTag):
                if asset.priorityTag == priorityTag { visibleAssets.append(asset) }
            }
        }
        let orderedVisibleAssets = visibleAssets

        self.assets = orderedVisibleAssets
        self.assetIDs = orderedVisibleAssets.map(\.id)
        self.assetIDSet = Set(assetIDs)
        self.positionByID = Dictionary(uniqueKeysWithValues: assetIDs.enumerated().map { ($1, $0) })
        var visibleKeepCount = 0
        var visibleRejectCount = 0
        var visiblePendingCount = 0
        for asset in orderedVisibleAssets {
            switch asset.ratingState {
            case .keep: visibleKeepCount += 1
            case .reject: visibleRejectCount += 1
            case .pending: visiblePendingCount += 1
            }
        }
        self.keepCount = visibleKeepCount
        self.rejectCount = visibleRejectCount
        self.pendingCount = visiblePendingCount
        self.basenameCompareGroups = includeBasenameCompareGroups
            ? Self.makeBasenameCompareGroups(
                from: orderedVisibleAssets,
                selectedFolderOrder: query.selectedFolderOrder,
                sortMode: query.sortMode,
                minimumGroupSize: 2
            )
            : []
    }

    public var totalCount: Int { assets.count }
    public var firstAsset: AssetRecord? { assets.first }
    public var lastAsset: AssetRecord? { assets.last }

    /// Fast path for rating/tag/rotation edits, which cannot change folder order.
    /// Text search can depend on tags, so that case deliberately uses a full query.
    mutating func updateDecisionRecords(_ updates: [UUID: AssetRecord]) -> Bool {
        guard query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        for index in scopedAssets.indices {
            let old = scopedAssets[index]
            guard let next = updates[old.id] else { continue }
            switch old.ratingState {
            case .keep: categorySummary.keepCount -= 1
            case .reject: categorySummary.rejectCount -= 1
            case .pending: categorySummary.pendingCount -= 1
            }
            switch next.ratingState {
            case .keep: categorySummary.keepCount += 1
            case .reject: categorySummary.rejectCount += 1
            case .pending: categorySummary.pendingCount += 1
            }
            if let tag = old.priorityTag {
                let count = categorySummary.priorityTagSummary.count(for: tag) - 1
                categorySummary.priorityTagSummary.counts[tag] = count > 0 ? count : nil
            }
            categorySummary.priorityTagSummary.record(next.priorityTag)
            scopedAssets[index] = next
        }
        for index in orderedScopedAssets.indices {
            if let next = updates[orderedScopedAssets[index].id] { orderedScopedAssets[index] = next }
        }
        assets = orderedScopedAssets.filter { asset in
            if query.pinnedAssetIDs.contains(asset.id) { return true }
            switch query.categoryFilter {
            case .all: return true
            case .rating(let rating): return asset.ratingState == rating
            case .priority(let tag): return asset.priorityTag == tag
            }
        }
        let nextIDs = assets.map(\.id)
        if nextIDs != assetIDs {
            assetIDs = nextIDs
            assetIDSet = Set(nextIDs)
            positionByID = Dictionary(uniqueKeysWithValues: nextIDs.enumerated().map { ($1, $0) })
        }
        keepCount = 0
        rejectCount = 0
        pendingCount = 0
        for asset in assets {
            switch asset.ratingState {
            case .keep: keepCount += 1
            case .reject: rejectCount += 1
            case .pending: pendingCount += 1
            }
        }
        basenameCompareGroups = basenameCompareGroups.map { group in
            group.map { updates[$0.id] ?? $0 }.filter { assetIDSet.contains($0.id) }
        }.filter { $0.count >= 2 }
        return true
    }

    mutating func refreshRecordPayloads(_ updates: [UUID: AssetRecord]) {
        func refresh(_ records: [AssetRecord]) -> [AssetRecord] {
            records.map { updates[$0.id] ?? $0 }
        }
        assets = refresh(assets)
        scopedAssets = refresh(scopedAssets)
        orderedScopedAssets = refresh(orderedScopedAssets)
        basenameCompareGroups = basenameCompareGroups.map(refresh)
    }

    public func contains(_ assetID: UUID) -> Bool {
        assetIDSet.contains(assetID)
    }

    public func index(of assetID: UUID) -> Int? {
        positionByID[assetID]
    }

    public func asset(afterMovingFrom currentID: UUID?, delta: Int) -> AssetRecord? {
        guard !assets.isEmpty else { return nil }
        let currentIndex = currentID.flatMap(index(of:)) ?? 0
        let nextIndex = max(0, min(currentIndex + delta, assets.count - 1))
        return assets[nextIndex]
    }

    public func idsSortedByVisibleOrder(_ ids: some Sequence<UUID>) -> [UUID] {
        return ids.sorted {
            positionByID[$0, default: .max] < positionByID[$1, default: .max]
        }
    }

    public func basenameCompareGroupsIncludingSingles() -> [[AssetRecord]] {
        Self.makeBasenameCompareGroups(
            from: assets,
            selectedFolderOrder: query.selectedFolderOrder,
            sortMode: query.sortMode,
            minimumGroupSize: 1
        )
    }

    public func sequentialCompareGroups(batchSize: Int, includeRemainder: Bool = false) -> [[AssetRecord]] {
        sequentialCompareGroups(
            from: assets,
            batchSize: batchSize,
            includeRemainder: includeRemainder
        )
    }

    public func filenameSequentialCompareGroups(
        batchSize: Int,
        includeRemainder: Bool = false
    ) -> [[AssetRecord]] {
        let filenameOrderedAssets = AssetFilenameSortKey.sorted(assets)

        return sequentialCompareGroups(
            from: filenameOrderedAssets,
            batchSize: batchSize,
            includeRemainder: includeRemainder
        )
    }

    private func sequentialCompareGroups(
        from orderedAssets: [AssetRecord],
        batchSize: Int,
        includeRemainder: Bool
    ) -> [[AssetRecord]] {
        guard batchSize >= 2,
              orderedAssets.count >= 2 || (includeRemainder && orderedAssets.count == 1) else {
            return []
        }

        var groups: [[AssetRecord]] = []
        var index = 0

        while index < orderedAssets.count {
            let endIndex = min(index + batchSize, orderedAssets.count)
            let group = Array(orderedAssets[index..<endIndex])
            if group.count >= 2 || (includeRemainder && group.count == 1) {
                groups.append(group)
            }
            index = endIndex
        }

        return groups
    }

    public static func basenameKey(for filename: String) -> String {
        AssetRecord.filenameKey(for: filename)
    }

    private static func makeBasenameCompareGroups(
        from assets: [AssetRecord],
        selectedFolderOrder: [String],
        sortMode: AssetSortMode,
        minimumGroupSize: Int
    ) -> [[AssetRecord]] {
        let folderOrder = Dictionary(uniqueKeysWithValues: selectedFolderOrder.enumerated().map { ($1, $0) })

        let groupedAssets = Dictionary(grouping: assets) {
            AssetRecord.comparisonFilenameKey(for: $0.filename)
        }
        let sortKeys = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, AssetFilenameSortKey($0)) })

        let assetOrder = Dictionary(uniqueKeysWithValues: assets.enumerated().map { ($1.id, $0) })
        let folderIndexByID = Dictionary(uniqueKeysWithValues: assets.map {
            ($0.id, selectedFolderOrderIndex(for: $0, folderOrder: folderOrder))
        })

        return groupedAssets
            .values
            .map { group in
                group.enumerated().sorted {
                    if !folderOrder.isEmpty {
                        let lhsFolderOrder = folderIndexByID[$0.element.id, default: .max]
                        let rhsFolderOrder = folderIndexByID[$1.element.id, default: .max]
                        if lhsFolderOrder != rhsFolderOrder {
                            return lhsFolderOrder < rhsFolderOrder
                        }
                    }

                    return compare($0.element, $1.element, sortMode: sortMode, sortKeys: sortKeys,
                        fallbackOffsets: ($0.offset, $1.offset))
                }.map(\.element)
            }
            .filter { $0.count >= minimumGroupSize }
            .sorted {
                let lhsOrder = $0.compactMap { assetOrder[$0.id] }.min() ?? .max
                let rhsOrder = $1.compactMap { assetOrder[$0.id] }.min() ?? .max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return compare($0[0], $1[0], sortMode: sortMode, sortKeys: sortKeys, fallbackOffsets: (0, 1))
            }
    }

    private static func selectedFolderOrderIndex(for asset: AssetRecord, folderOrder: [String: Int]) -> Int {
        var minimum = Int.max
        for (path, index) in folderOrder where index < minimum {
            if asset.relativePath == path || asset.relativePath.hasPrefix(path + "/") { minimum = index }
        }
        return minimum
    }

    private static func orderAssetsBySelectedFolders(
        _ assets: [AssetRecord],
        selectedFolderOrder: [String],
        sortMode: AssetSortMode
    ) -> [AssetRecord] {
        let folderOrder = Dictionary(uniqueKeysWithValues: selectedFolderOrder.enumerated().map { ($1, $0) })
        let sortKeys = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, AssetFilenameSortKey($0)) })

        // Resolve folder membership once per record, not twice in every sort
        // comparison (N log N allocations on a large multi-folder workspace).
        let folderIndexByID = Dictionary(uniqueKeysWithValues: assets.map {
            ($0.id, selectedFolderOrderIndex(for: $0, folderOrder: folderOrder))
        })
        return assets.enumerated().sorted {
            if !selectedFolderOrder.isEmpty {
                let lhsFolderOrder = folderIndexByID[$0.element.id, default: .max]
                let rhsFolderOrder = folderIndexByID[$1.element.id, default: .max]
                if lhsFolderOrder != rhsFolderOrder {
                    return lhsFolderOrder < rhsFolderOrder
                }
            }

            return compare($0.element, $1.element, sortMode: sortMode, sortKeys: sortKeys,
                fallbackOffsets: ($0.offset, $1.offset))
        }.map(\.element)
    }

    private static func compare(
        _ lhs: AssetRecord,
        _ rhs: AssetRecord,
        sortMode: AssetSortMode,
        sortKeys: [UUID: AssetFilenameSortKey],
        fallbackOffsets: (Int, Int)
    ) -> Bool {
        switch sortMode {
        case .addedDate:
            if let lhsDate = lhs.addedToDirectoryDate, let rhsDate = rhs.addedToDirectoryDate, lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            if lhs.addedToDirectoryDate != nil && rhs.addedToDirectoryDate == nil {
                return true
            }
            if lhs.addedToDirectoryDate == nil && rhs.addedToDirectoryDate != nil {
                return false
            }
        case .filename:
            break
        }

        let filenameOrder = (sortKeys[lhs.id] ?? AssetFilenameSortKey(lhs))
            .compare(to: sortKeys[rhs.id] ?? AssetFilenameSortKey(rhs))
        if filenameOrder != .orderedSame {
            return filenameOrder == .orderedAscending
        }

        return fallbackOffsets.0 < fallbackOffsets.1
    }
}
