import Combine
import Foundation

private struct AssetSelectionKey: Hashable {
    let libraryPath: String
    let relativePath: String
}

private struct WorkspacePresentationState {
    let selectedLibraryPath: String?
    let selectedFolderPath: String?
    let selectedFolderPaths: Set<String>
    let selectedFolderOrder: [String]
    let selectedAssetRelativePaths: [AssetSelectionKey]
    let focusedAssetRelativePath: AssetSelectionKey?
    let compareSessionRelativePaths: [AssetSelectionKey]
    let compareFolderPaths: [String]
    let compareFocusedRelativePath: AssetSelectionKey?
    let compareOverlayRelativePath: AssetSelectionKey?
    let compareTemporaryOverlaySlot: Int?
    let mode: WorkspaceMode
    let searchText: String
    let showUnreviewedOnly: Bool
    let viewedCompareGroupKeys: Set<String>
    let categoryFilter: AssetCategoryFilter
    let assetSortMode: AssetSortMode
}

private struct PreservingWorkspaceMergeResult {
    let libraries: [LibraryFolder]
    let assets: [AssetRecord]
    let changedAssetIDs: Set<UUID>
}

private struct ContentMatchKey: Hashable, Sendable {
    let referenceAssetID: UUID
    let targetFolderPath: String
}

private struct ContentMatchingAssetSignature: Hashable, Sendable {
    let assetID: UUID
    let fileSizeBytes: Int64
    let modificationMilliseconds: Int64
}

private struct ContentMatchingSignature: Hashable, Sendable {
    let folderOrder: [String]
    let assets: [ContentMatchingAssetSignature]
}

private struct ContentMatchingColumnPlan: Sendable {
    let targetFolderPath: String
    let referenceAssetIDs: [UUID]
    let targetAssetIDs: [UUID]
}

private struct FolderComparisonSnapshot {
    var rows: [[AssetRecord?]]
    var groups: [[AssetRecord]]
    let rowIndexByAssetID: [UUID: Int]
    var completeRows: [[AssetRecord?]]
    var missingGroups: [MissingCompareGroup]
    let missingAssetCount: Int
    private let completeIndexByRowIndex: [Int: Int]
    private let missingIndexByRowIndex: [Int: Int]

    init(rows: [[AssetRecord?]], folderOrder: [String]) {
        self.rows = rows
        groups = rows.map { $0.compactMap(\.self) }
        var indices: [UUID: Int] = [:]
        var complete: [[AssetRecord?]] = []
        var missing: [MissingCompareGroup] = []
        var missingCount = 0
        var completeIndices: [Int: Int] = [:]
        var missingIndices: [Int: Int] = [:]
        for (index, row) in rows.enumerated() {
            for asset in groups[index] { indices[asset.id] = index }
            let absent = zip(folderOrder, row).compactMap { $1 == nil ? $0 : nil }
            if absent.isEmpty {
                completeIndices[index] = complete.count
                complete.append(row)
            } else {
                missingIndices[index] = missing.count
                missingCount += absent.count
                missing.append(MissingCompareGroup(
                    basenameKey: "ordered-row-\(index)",
                    displayName: groups[index].first?.filename ?? "第 \(index + 1) 组",
                    presentAssets: groups[index], missingFolderPaths: absent, slots: row
                ))
            }
        }
        rowIndexByAssetID = indices
        completeRows = complete
        missingGroups = missing
        missingAssetCount = missingCount
        completeIndexByRowIndex = completeIndices
        missingIndexByRowIndex = missingIndices
    }

    mutating func refreshPayloads(_ updates: [UUID: AssetRecord]) {
        for index in Set(updates.keys.compactMap { rowIndexByAssetID[$0] }) {
            let row = rows[index].map { asset in asset.map { updates[$0.id] ?? $0 } }
            rows[index] = row
            groups[index] = row.compactMap(\.self)
            if let completeIndex = completeIndexByRowIndex[index] { completeRows[completeIndex] = row }
            if let missingIndex = missingIndexByRowIndex[index] {
                missingGroups[missingIndex].slots = row
                missingGroups[missingIndex].presentAssets = groups[index]
            }
        }
    }
}

private struct FinderTagWriteOperation: Sendable {
    let assetID: UUID
    let fileURL: URL
    let updatedTags: [FinderTag]
}

private struct FinderTagReadTarget: Sendable {
    let assetID: UUID
    let fileURL: URL
}

private struct FinderTagBatchResult: Sendable {
    var tagsByID: [UUID: [FinderTag]] = [:]
    var pendingUpdates: [String: PendingFinderTagEdit] = [:]
    var removedKeys: Set<String> = []
    var failures: [String] = []
}

private struct AssetFileRotationOperation: Sendable {
    let assetID: UUID
    let fileURL: URL
    let finderTags: [FinderTag]
}

@MainActor
public final class AppState: ObservableObject {
    private static let fallbackCompareBatchSize = 2

    @Published public private(set) var libraries: [LibraryFolder] = []
    @Published public private(set) var assets: [AssetRecord] = []
    @Published public private(set) var compareGroups: [CompareGroup] = []
    @Published public private(set) var compareSession = CompareSessionState()
    @Published public private(set) var singleFolderCompareGroupSize = AppState.fallbackCompareBatchSize {
        didSet { invalidateCompareGroupsCache() }
    }
    @Published public var mode: WorkspaceMode = .grid
    @Published public private(set) var selectedLibraryID: UUID?
    @Published public private(set) var selectedFolderPath: String?
    @Published public private(set) var selectedFolderPaths: Set<String> = []
    @Published public private(set) var selectedFolderOrder: [String] = []
    @Published public var searchText = "" {
        didSet { rebuildVisibleSnapshot() }
    }
    @Published public var keepFolderPath = ""
    @Published public var rejectFolderPath = ""
    @Published public var showUnreviewedOnly = false {
        didSet {
            rebuildVisibleSnapshotAndNormalizeSelection()
            normalizeCompareSessionForVisibleGroups()
        }
    }
    @Published public private(set) var categoryFilter: AssetCategoryFilter = .all {
        didSet {
            rebuildVisibleSnapshotAndNormalizeSelection()
            normalizeCompareSessionForVisibleGroups()
        }
    }
    @Published public private(set) var assetSortMode: AssetSortMode = .filename {
        didSet {
            rebuildVisibleSnapshotAndNormalizeSelection()
            normalizeCompareSessionForVisibleGroups()
        }
    }
    @Published public var isLoading = false
    @Published public private(set) var isMatchingImageContent = false {
        didSet { if oldValue != isMatchingImageContent { invalidateCompareGroupsCache() } }
    }
    @Published public private(set) var exportProgress: ExportProgress?
    @Published public private(set) var imageRefreshToken = UUID()
    @Published private var assetImageRefreshTokens: [UUID: UUID] = [:]
    @Published private var contentMatchedAssetIDByKey: [ContentMatchKey: UUID] = [:] {
        didSet { invalidateCompareGroupsCache() }
    }
    @Published public private(set) var finderTagErrorMessage: String?
    @Published public private(set) var isUpdatingFinderTags = false
    @Published public private(set) var pendingFinderTagCount = 0
    @Published public private(set) var priorityTagDefinitions = PriorityTagDefinition.defaults
    @Published public private(set) var priorityTagCatalogErrorMessage: String?
    @Published public private(set) var rotationErrorMessage: String?
    @Published public private(set) var isRotatingLocalFiles = false
    @Published private var selection = SelectionModel()
    @Published private var visibleSnapshot = VisibleAssetSnapshot()

    private let autoRefreshDebounceNanoseconds: UInt64 = 400_000_000
    private let localFileMutationRefreshSuppressionInterval: TimeInterval = 5
    private var indexingService: any IndexingService
    private let exportExecutor: any ExportExecuting
    private let inspectionService: any AssetInspectionService
    private let finderTagService: any FinderTagSyncing
    private let pendingFinderTagStore: any PendingFinderTagPersisting
    private var pendingFinderTagEdits: [String: PendingFinderTagEdit] = [:]
    private let imageContentFingerprintService: any ImageContentFingerprinting
    private let assetFileRotationService: any AssetFileRotating
    private let workspaceRootsStore: any WorkspaceRootsPersisting
    private let decisionStore: any AssetDecisionPersisting
    private let priorityTagCatalogStore: any PriorityTagCatalogPersisting
    private let indexingServiceFactory: @Sendable ([String]) -> any IndexingService
    private let workspaceFileWatcherFactory: @Sendable ([String], @escaping @Sendable () -> Void) -> any WorkspaceFileWatching
    private let preferredStartupRoots: [String]?
    private let compareCoordinator = CompareSessionCoordinator()
    private let fileMutationGate = FileMutationGate()
    private var activeTagOperations = 0
    private var activeRotationOperations = 0
    private var didBootstrap = false
    private var workspaceRootPaths: [String] = []
    private var workspaceFileWatcher: (any WorkspaceFileWatching)?
    private var pendingAutoRefreshTask: Task<Void, Never>?
    private var contentMatchingTask: Task<Void, Never>?
    private var contentMatchingSignature: ContentMatchingSignature?
    private var contentMatchingGeneration = UUID()
    private var isReloadingWorkspace = false
    private var needsReloadAfterCurrentPass = false
    private var assetIndexByID: [UUID: AssetRecord] = [:]
    private var assetArrayIndexByID: [UUID: Int] = [:]
    private var comparisonGroupIndexByAssetID: [UUID: Int] = [:]
    private var libraryPathByID: [UUID: String] = [:]
    private var libraryAssetCountCache: [UUID: Int] = [:]
    private var folderTreeCache: [UUID: [FolderTreeNode]] = [:]
    private var metadataLoadingAssetIDs: Set<UUID> = []
    private var viewedCompareGroupKeys: Set<String> = []
    private var savedDecisionSnapshot: [String: PersistedAssetDecision] = [:]
    private var currentDecisionSnapshot: [String: PersistedAssetDecision] = [:]
    private var suppressGlobalImageRefreshUntil = Date.distantPast
    private var cachedCompareFolderOrder: [String]?
    private var cachedCompareGroupSize: Int?
    private var cachedBasenameCompareGroups: [[AssetRecord]]?
    private var cachedFilteredComparison: FolderComparisonSnapshot?
    private var cachedScopedComparison: FolderComparisonSnapshot?
    private var cachedEffectiveCompareFolderOrder: [String]?
    private var cachedKnownFinderTags: [FinderTag]?
    private var cachedHasAnyTriageTags = false
    private var triageTaggedAssetCount = 0
    private var cachedPriorityTagSummary = PriorityTagSummary()
    private var cachedFinderTagColorSummary: FinderTagColorSummary?
    private var cachedExportScopeSummary: AssetCategorySummary?

    public init(
        indexingService: any IndexingService,
        exportExecutor: any ExportExecuting = FileSystemExportService(synchronizesFinderTags: false),
        inspectionService: any AssetInspectionService = NoopAssetInspectionService(),
        finderTagService: any FinderTagSyncing = FileSystemFinderTagService(),
        pendingFinderTagStore: any PendingFinderTagPersisting = MemoryPendingFinderTagStore(),
        imageContentFingerprintService: any ImageContentFingerprinting = FileSystemImageContentFingerprintService(),
        assetFileRotationService: any AssetFileRotating = FileSystemAssetRotationService(),
        workspaceRootsStore: any WorkspaceRootsPersisting = NoopWorkspaceRootsStore(),
        decisionStore: any AssetDecisionPersisting = NoopAssetDecisionStore(),
        priorityTagCatalogStore: any PriorityTagCatalogPersisting = NoopPriorityTagCatalogStore(),
        indexingServiceFactory: @escaping @Sendable ([String]) -> any IndexingService = { FileSystemIndexingService(rootPaths: $0, readsFinderTags: false) },
        workspaceFileWatcherFactory: @escaping @Sendable ([String], @escaping @Sendable () -> Void) -> any WorkspaceFileWatching = { WorkspaceFileWatcher(rootPaths: $0, onChange: $1) },
        preferredStartupRoots: [String]? = nil
    ) {
        self.indexingService = indexingService
        self.exportExecutor = exportExecutor
        self.inspectionService = inspectionService
        self.finderTagService = finderTagService
        self.pendingFinderTagStore = pendingFinderTagStore
        self.imageContentFingerprintService = imageContentFingerprintService
        self.assetFileRotationService = assetFileRotationService
        self.workspaceRootsStore = workspaceRootsStore
        self.decisionStore = decisionStore
        self.priorityTagCatalogStore = priorityTagCatalogStore
        self.indexingServiceFactory = indexingServiceFactory
        self.workspaceFileWatcherFactory = workspaceFileWatcherFactory
        self.preferredStartupRoots = preferredStartupRoots
        self.savedDecisionSnapshot = decisionStore.loadDecisions()
        do {
            priorityTagDefinitions = PriorityTagCatalog.normalized(try priorityTagCatalogStore.load())
        } catch {
            priorityTagCatalogErrorMessage = "无法读取 P 标签设置，原设置未覆盖：\(error.localizedDescription)"
        }
        do {
            pendingFinderTagEdits = try pendingFinderTagStore.load()
        } catch {
            finderTagErrorMessage = "无法读取本机待同步标签记录，未覆盖原记录：\(error.localizedDescription)"
        }
    }

    public var selectedAssetID: UUID? {
        get { selection.focusedAssetID }
        set { select(assetID: newValue) }
    }

    public var selectedAssetIDs: Set<UUID> {
        get { selection.assetIDs }
        set { setSelection(assetIDs: newValue) }
    }

    public func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        if let startupRoots = preferredStartupRoots {
            configureWorkspaceRoots(startupRoots)
        }
        await reloadWorkspace(resetPresentation: true)
    }

    public func reloadWorkspace() async {
        await reloadWorkspace(resetPresentation: true)
    }

    public func reloadWorkspace(resetPresentation: Bool, changedPaths: Set<String>? = nil) async {
        if isReloadingWorkspace {
            needsReloadAfterCurrentPass = true
            return
        }

        var refreshPaths = changedPaths
        repeat {
            needsReloadAfterCurrentPass = false
            isReloadingWorkspace = true
            await performWorkspaceReload(resetPresentation: resetPresentation, changedPaths: refreshPaths)
            refreshPaths = nil // Coalesced events can refer to other paths; reconcile all on retry.
            isReloadingWorkspace = false
        } while needsReloadAfterCurrentPass
    }

    public func requestPreservingWorkspaceReload() async {
        guard !isReloadingWorkspace else { return }
        await reloadWorkspace(resetPresentation: false)
    }

    public func scheduleAutoRefresh() {
        guard !workspaceRootPaths.isEmpty else { return }
        pendingAutoRefreshTask?.cancel()
        pendingAutoRefreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: autoRefreshDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self.pendingAutoRefreshTask = nil
            await self.reloadWorkspace(resetPresentation: false, changedPaths: self.workspaceFileWatcher?.takeChangedPaths())
        }
    }

    private func performWorkspaceReload(resetPresentation: Bool, changedPaths: Set<String>? = nil) async {
        let lockedIDs = Set(assets.map(\.id))
        await fileMutationGate.acquire(lockedIDs)
        defer { fileMutationGate.release(lockedIDs) }
        guard !Task.isCancelled else { return }
        let presentation = resetPresentation ? nil : capturePresentationState()
        if resetPresentation {
            contentMatchingTask?.cancel()
            contentMatchingTask = nil
            contentMatchingGeneration = UUID()
            contentMatchingSignature = nil
            isMatchingImageContent = false
        }
        isLoading = true
        defer {
            isLoading = false
            scheduleContentMatchingForSelectedFolders()
        }

        do {
            if resetPresentation {
                var didReceiveSnapshot = false
                let sessionDecisions = decisionsForRestoringWorkspace()
                resetWorkspacePresentation()

                for try await snapshot in indexingService.loadWorkspaceSnapshots() {
                    didReceiveSnapshot = true
                    applyWorkspaceSnapshot(snapshot, resetPresentation: false, restoring: sessionDecisions)
                }

                if !didReceiveSnapshot {
                    applyWorkspaceSnapshot(emptyWorkspaceSnapshot(), resetPresentation: false, restoring: sessionDecisions)
                }
            } else {
                let snapshot: WorkspaceSnapshot
                if let changedPaths {
                    snapshot = try await indexingService.refreshWorkspace(
                        WorkspaceSnapshot(libraries: libraries, assets: assets, compareGroups: compareGroups,
                            keepFolderPath: keepFolderPath, rejectFolderPath: rejectFolderPath), changedPaths: changedPaths)
                } else {
                    snapshot = try await indexingService.loadWorkspace()
                }
                applyWorkspaceSnapshot(snapshot, presentation: presentation, resetPresentation: false)
            }
        } catch {
            if resetPresentation {
                applyWorkspaceSnapshot(emptyWorkspaceSnapshot(), resetPresentation: true)
            } else {
                applyFailedPreservingReload(presentation)
            }
        }
    }

    public var filteredAssets: [AssetRecord] {
        visibleSnapshot.assets
    }

    public var selectedAsset: AssetRecord? {
        if let selectedAssetID {
            return assetByID(selectedAssetID)
        }
        return nil
    }

    public var compareSelectionIDs: [UUID] { compareSession.selectionIDs }

    public var compareAssets: [AssetRecord] {
        compareSelectionIDs.compactMap(assetByID)
    }

    /// Screen positions are independent of the number of files present in a group.
    public var comparePaneAssets: [AssetRecord?] {
        let presentAssets = compareAssets
        guard !compareSession.folderPaths.isEmpty else { return presentAssets.map(Optional.some) }
        return compareSession.folderPaths.map { folderPath in
            presentAssets.first { assetMatchesFolder($0, folderPath: folderPath) }
        }
    }

    public func compareAsset(atPane index: Int) -> AssetRecord? {
        let panes = comparePaneAssets
        guard panes.indices.contains(index) else { return nil }
        return panes[index]
    }

    public var isSingleImageCompareMode: Bool {
        comparePaneAssets.count == 1
    }

    public var isShowingCompareOverview: Bool {
        compareSession.focusedAssetID == nil
    }

    public var compareFocusedAsset: AssetRecord? {
        compareCoordinator.focusedAssetID(in: compareSession).flatMap(assetByID)
    }

    public var compareOverlayAsset: AssetRecord? {
        compareCoordinator.overlayAssetID(in: compareSession).flatMap(assetByID)
    }

    public var temporaryCompareOverlayAsset: AssetRecord? {
        guard let temporaryOverlaySlot = compareSession.temporaryOverlaySlot,
              overlayCompareCandidates.indices.contains(temporaryOverlaySlot) else {
            return nil
        }

        return overlayCompareCandidates[temporaryOverlaySlot]
    }

    public var effectiveCompareOverlayAsset: AssetRecord? {
        temporaryCompareOverlayAsset ?? compareOverlayAsset
    }

    public var totalCount: Int { filteredAssets.count }
    public var visibleThumbnailAssetCount: Int {
        filteredAssets.count
    }
    public var compareFolderOrder: [String] {
        if let cachedEffectiveCompareFolderOrder { return cachedEffectiveCompareFolderOrder }
        let folders = effectiveCompareFolderOrder()
        cachedEffectiveCompareFolderOrder = folders
        return folders
    }
    public var basenameCompareGroups: [[AssetRecord]] {
        let folderOrder = compareFolderOrder
        if folderOrder.count > 1 {
            return filteredComparison.groups
        }

        if cachedCompareFolderOrder == folderOrder,
           cachedCompareGroupSize == singleFolderCompareGroupSize,
           let cachedBasenameCompareGroups {
            return cachedBasenameCompareGroups
        }

        let groups = visibleSnapshot.filenameSequentialCompareGroups(
            batchSize: singleFolderCompareGroupSize,
            includeRemainder: true
        )
        cachedCompareFolderOrder = folderOrder
        cachedCompareGroupSize = singleFolderCompareGroupSize
        cachedBasenameCompareGroups = groups
        return groups
    }
    public var viewerCompareGroups: [[AssetRecord]] {
        basenameCompareGroups
    }
    public var visibleCompareRows: [[AssetRecord?]] {
        let folderOrder = compareFolderOrder
        if folderOrder.count > 1 {
            return filteredComparison.rows
        }

        let groups = basenameCompareGroups
        let columnCount = max(folderOrder.count, groups.map(\.count).max() ?? 0)
        guard columnCount > 0 else { return [] }

        if !folderOrder.isEmpty {
            return groups.map { group in
                folderOrder.map { folderPath in
                    group.first { asset in
                        asset.relativePath == folderPath || asset.relativePath.hasPrefix(folderPath + "/")
                    }
                }
            }
        }

        return groups.map { group in
            group.map(Optional.some) + Array(repeating: nil, count: max(columnCount - group.count, 0))
        }
    }
    public var visibleCompleteCompareRows: [[AssetRecord?]] {
        filteredComparison.completeRows
    }
    public var missingCompareGroups: [MissingCompareGroup] {
        guard !isMatchingImageContent else { return [] }
        return scopedComparison.missingGroups
    }
    public var missingCompareAssetCount: Int {
        isMatchingImageContent ? 0 : scopedComparison.missingAssetCount
    }
    public var visibleAssetColumnsBySelectedFolder: [(folderPath: String, assets: [AssetRecord])] {
        compareFolderOrder.map { folderPath in
            let columnAssets = filteredAssets.filter { asset in
                asset.relativePath == folderPath || asset.relativePath.hasPrefix(folderPath + "/")
            }
            return (folderPath: folderPath, assets: columnAssets)
        }
    }
    public func isAssetInViewedCompareGroup(_ assetID: UUID) -> Bool {
        guard let asset = assetByID(assetID) else { return false }
        return viewedCompareGroupKeys.contains(asset.compareAlignmentKey)
    }
    public var basenameCompareGroupCount: Int { basenameCompareGroups.count }
    public var currentBasenameCompareGroupNumber: Int? {
        guard let selectedAssetID,
              let selected = assetByID(selectedAssetID) else { return nil }

        if compareFolderOrder.count > 1 {
            return filteredComparison.rowIndexByAssetID[selected.id].map { $0 + 1 }
        }

        let key = selected.compareAlignmentKey
        return basenameCompareGroups.firstIndex { group in
            group.contains { $0.compareAlignmentKey == key }
        }.map { $0 + 1 }
    }
    public var currentCompareGroupScrollTargetAssetID: UUID? {
        guard compareFolderOrder.count > 1 else {
            return selectedAssetID
        }

        let anchorID = compareSelectionIDs.first ?? selectedAssetID
        guard let anchorID,
              let index = filteredComparison.rowIndexByAssetID[anchorID] else {
            return selectedAssetID
        }
        return filteredComparison.groups[index].first?.id ?? selectedAssetID
    }
    public var keepCount: Int { visibleSnapshot.keepCount }
    public var rejectCount: Int { visibleSnapshot.rejectCount }
    public var pendingCount: Int { visibleSnapshot.pendingCount }
    public var allAssetCount: Int { assets.count }
    public var knownFinderTags: [FinderTag] {
        if let cachedKnownFinderTags { return cachedKnownFinderTags }
        let tags = FinderTag.normalized(assets.flatMap(\.finderTags)).sorted { lhs, rhs in
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            return nameOrder == .orderedSame ? lhs.color.rawValue < rhs.color.rawValue : nameOrder == .orderedAscending
        }
        cachedKnownFinderTags = tags
        return tags
    }
    public var hasAnyTriageTags: Bool {
        cachedHasAnyTriageTags
    }
    public var priorityTagSummary: PriorityTagSummary {
        cachedPriorityTagSummary
    }
    public var priorityTags: [PriorityTag] { priorityTagDefinitions.map(\.tag) }

    public func priorityTagDisplayName(_ tag: PriorityTag) -> String {
        priorityTagDefinitions.first { $0.tag == tag }?.name ?? tag.rawValue
    }

    public func renamePriorityTag(_ tag: PriorityTag, to name: String) throws {
        guard let index = priorityTagDefinitions.firstIndex(where: { $0.tag == tag }) else {
            throw PriorityTagCatalogError.missingTag
        }
        let normalized = try PriorityTagCatalog.validatedName(name, for: tag, in: priorityTagDefinitions)
        var updated = priorityTagDefinitions
        updated[index].name = normalized
        try priorityTagCatalogStore.save(updated)
        priorityTagDefinitions = updated
        priorityTagCatalogErrorMessage = nil
        rebuildVisibleSnapshot()
    }

    @discardableResult
    public func addPriorityTag() throws -> PriorityTag {
        let maximum = priorityTagDefinitions.map { $0.tag.index }.max() ?? 2
        guard maximum < Int.max else { throw PriorityTagCatalogError.tooManyTags }
        let tag = PriorityTag(index: maximum + 1)
        let updated = priorityTagDefinitions + [PriorityTagDefinition(tag: tag)]
        try priorityTagCatalogStore.save(updated)
        priorityTagDefinitions = updated
        priorityTagCatalogErrorMessage = nil
        return tag
    }
    public var finderTagColorSummary: FinderTagColorSummary {
        if let cachedFinderTagColorSummary { return cachedFinderTagColorSummary }
        let summary = FinderTagColorSummary(assets: assets)
        cachedFinderTagColorSummary = summary
        return summary
    }
    public var categorySummary: AssetCategorySummary {
        visibleSnapshot.categorySummary
    }
    public var passRate: Double {
        let summary = visibleSnapshot.categorySummary
        guard summary.totalCount > 0 else { return 0 }
        return Double(summary.totalCount - summary.rejectCount) / Double(summary.totalCount)
    }
    public var activeFilterDescription: String {
        guard let selectedLibraryID,
              let library = libraries.first(where: { $0.id == selectedLibraryID }) else {
            return descriptionWithCategory("全部资源")
        }

        if selectedFolderPaths.count > 1 {
            return descriptionWithCategory("\(library.displayName) / 已选 \(selectedFolderPaths.count) 个目录")
        }

        if let selectedFolderPath, !selectedFolderPath.isEmpty {
            return descriptionWithCategory("\(library.displayName) / \(selectedFolderPath)")
        }

        return descriptionWithCategory(library.displayName)
    }

    private func descriptionWithCategory(_ baseDescription: String) -> String {
        guard categoryFilter != .all else { return baseDescription }
        if case .priority(let tag) = categoryFilter {
            return "\(baseDescription) / \(priorityTagDisplayName(tag))"
        }
        return "\(baseDescription) / \(categoryFilter.title)"
    }

    public func selectCategoryFilter(_ filter: AssetCategoryFilter) {
        categoryFilter = filter
    }

    public func selectAssetSortMode(_ sortMode: AssetSortMode) {
        assetSortMode = sortMode
    }

    public func selectLibrary(_ libraryID: UUID?) {
        selectedLibraryID = libraryID
        selectedFolderPath = nil
        selectedFolderPaths = []
        selectedFolderOrder = []
        rebuildVisibleSnapshot()
        normalizeSelectionForVisibleAssets()
    }

    public func selectFolder(in libraryID: UUID, relativePath: String?) {
        selectedLibraryID = libraryID
        selectedFolderPath = relativePath
        selectedFolderPaths = Set(relativePath.map { [$0] } ?? [])
        selectedFolderOrder = relativePath.map { [$0] } ?? []
        rebuildVisibleSnapshot()
        normalizeSelectionForVisibleAssets()
    }

    public func toggleFolderSelection(in libraryID: UUID, relativePath: String?) {
        guard let relativePath else {
            selectLibrary(libraryID)
            return
        }

        if selectedLibraryID != libraryID {
            selectedLibraryID = libraryID
            selectedFolderPaths = [relativePath]
            selectedFolderOrder = [relativePath]
        } else if selectedFolderPaths.contains(relativePath) {
            selectedFolderPaths.remove(relativePath)
            selectedFolderOrder.removeAll { $0 == relativePath }
        } else {
            selectedFolderPaths.insert(relativePath)
            selectedFolderOrder.append(relativePath)
        }

        selectedFolderPath = selectedFolderOrder.count == 1 ? selectedFolderOrder.first : nil
        rebuildVisibleSnapshot()
        normalizeSelectionForVisibleAssets()
    }

    private func configureWorkspaceRoots(_ rootPaths: [String]) {
        let normalizedRoots = rootPaths
            .map { NSString(string: $0).expandingTildeInPath }
            .filter { !$0.isEmpty }
        workspaceRootPaths = normalizedRoots
        pendingAutoRefreshTask?.cancel()
        pendingAutoRefreshTask = nil
        contentMatchingTask?.cancel()
        contentMatchingTask = nil
        contentMatchingSignature = nil
        contentMatchedAssetIDByKey = [:]
        isMatchingImageContent = false
        needsReloadAfterCurrentPass = false
        workspaceFileWatcher?.stop()
        workspaceFileWatcher = nil

        indexingService = indexingServiceFactory(normalizedRoots)

        guard !normalizedRoots.isEmpty else {
            workspaceRootsStore.clearRootPaths()
            return
        }

        let watcher = workspaceFileWatcherFactory(normalizedRoots) { [weak self] in
            Task { @MainActor in
                self?.scheduleAutoRefresh()
            }
        }
        workspaceFileWatcher = watcher
        watcher.start()
    }

    public func useWorkspaceRoots(_ rootPaths: [String]) async {
        mode = .grid
        didBootstrap = true
        configureWorkspaceRoots(rootPaths)
        await reloadWorkspace(resetPresentation: true)
    }

    public func useSampleWorkspace() async {
        mode = .grid
        didBootstrap = true
        workspaceRootPaths = []
        pendingAutoRefreshTask?.cancel()
        pendingAutoRefreshTask = nil
        needsReloadAfterCurrentPass = false
        workspaceFileWatcher?.stop()
        workspaceFileWatcher = nil
        workspaceRootsStore.clearRootPaths()
        indexingService = MockIndexingService()
        await reloadWorkspace(resetPresentation: true)
    }

    public func clearSessionCaches() {
        pendingAutoRefreshTask?.cancel()
        pendingAutoRefreshTask = nil
        contentMatchingTask?.cancel()
        contentMatchingTask = nil
        contentMatchingSignature = nil
        contentMatchedAssetIDByKey = [:]
        isMatchingImageContent = false
        workspaceFileWatcher?.stop()
        workspaceFileWatcher = nil
        workspaceRootPaths = []
        workspaceRootsStore.clearRootPaths()
        decisionStore.clearDecisions()
        savedDecisionSnapshot = [:]
        currentDecisionSnapshot = [:]
    }

    public func importWorkspaceFolders(from urls: [URL]) async {
        let rootPaths = urls.compactMap(normalizedDirectoryPath(for:))
            .reduce(into: [String]()) { result, path in
                if !result.contains(path) {
                    result.append(path)
                }
            }

        guard !rootPaths.isEmpty else { return }
        await useWorkspaceRoots(rootPaths)
    }

    public func folderTree(for libraryID: UUID) -> [FolderTreeNode] {
        folderTreeCache[libraryID] ?? []
    }

    public func select(assetID: UUID?) {
        selection.select(assetID)
        if let assetID {
            scheduleMetadataLoad(for: [assetID])
        }
    }

    public func toggleSelection(assetID: UUID) {
        selection.toggle(assetID, orderedBy: assetOrder)
        scheduleMetadataLoad(for: Array(selection.assetIDs))
    }

    public func setSelection(assetIDs: Set<UUID>) {
        selection.set(assetIDs, orderedBy: assetOrder)
        scheduleMetadataLoad(for: Array(assetIDs))
    }

    public func clearSelection() {
        selection.clear()
    }

    public func enterCompareMode() {
        let ordered = selection.orderedAssetIDs(by: assetOrder)
        if ordered.isEmpty {
            if let selectedAssetID {
                enterCompareMode(forAssetIDs: [selectedAssetID], focusedAssetID: selectedAssetID)
                return
            }
            enterCompareModeForCurrentBasenameGroup()
            return
        }
        if compareFolderOrder.count <= 1, ordered.count >= 2 {
            singleFolderCompareGroupSize = ordered.count
        }
        let focusedAssetID = ordered.count == 1 ? ordered.first : nil
        let compareOrdered = ordered
        compareSession = compareCoordinator.makeSession(selectionIDs: compareOrdered, focusedAssetID: focusedAssetID)
        if ordered.count > 1, compareFolderOrder.count > 1,
           visibleCompareRows.contains(where: {
               $0.compactMap { $0?.id } == ordered
           }) {
            compareSession.folderPaths = compareFolderOrder
        }
        selection.setOrdered(compareOrdered)
        selection.focusedAssetID = focusedAssetID ?? compareOrdered.first
        mode = .compare
        if !showUnreviewedOnly {
            markCompareGroupsViewed(for: compareOrdered)
        }
        scheduleMetadataLoad(for: compareOrdered)
    }

    public func enterCompareModeForCurrentBasenameGroup() {
        guard let selected = selectedAsset ?? visibleSnapshot.firstAsset else { return }
        enterCompareMode(forBasenameKey: selected.compareAlignmentKey)
    }

    public func enterCompareModeForVisibleGroup(containing assetID: UUID, focusedAssetID: UUID? = nil) {
        guard let asset = assetByID(assetID) else { return }

        if compareFolderOrder.count > 1,
           let group = visibleCompareRows
            .first(where: { row in row.contains { $0?.id == assetID } })?
            .compactMap(\.self),
           !group.isEmpty {
            enterCompareMode(forAssetIDs: group.map(\.id), focusedAssetID: focusedAssetID, preserveFolderSlots: true)
            return
        }

        enterCompareMode(forBasenameKey: asset.compareAlignmentKey, focusedAssetID: focusedAssetID)
    }

    public func enterSingleImageViewer(assetID: UUID) {
        enterCompareMode(forAssetIDs: [assetID], focusedAssetID: assetID)
    }

    public func jumpToBasenameCompareGroup(number: Int, enterCompare: Bool = true) {
        let index = number - 1
        let groups = viewerCompareGroups
        guard groups.indices.contains(index),
              let firstAsset = groups[index].first else { return }

        let groupIDs = groups[index].map(\.id)
        if enterCompare || mode == .compare {
            enterCompareMode(forAssetIDs: groups[index].map(\.id), focusedAssetID: nil, preserveFolderSlots: true)
        } else {
            selection.set(Set(groupIDs), orderedBy: assetOrder)
            selection.focusedAssetID = firstAsset.id
            scheduleMetadataLoad(for: groupIDs)
        }
    }

    @discardableResult
    public func stepBasenameCompareGroup(delta: Int) -> Bool {
        if isSingleImageCompareMode {
            return stepSingleImageViewer(delta: delta)
        }

        let groups = viewerCompareGroups
        guard !groups.isEmpty else { return false }

        let anchorID = compareSelectionIDs.first ?? selectedAssetID
        let visibleCurrentIndex = anchorID.flatMap { id in
            if compareFolderOrder.count > 1 { return filteredComparison.rowIndexByAssetID[id] }
            return groups.firstIndex { group in
                group.contains { $0.id == id }
            }
        }
        let currentIndex = visibleCurrentIndex ?? (delta > 0 ? -1 : groups.count)
        let nextIndex = max(0, min(currentIndex + delta, groups.count - 1))
        guard nextIndex != currentIndex,
              !groups[nextIndex].isEmpty else {
            return false
        }

        enterCompareMode(
            forAssetIDs: groups[nextIndex].map(\.id),
            focusedAssetID: compareFolderOrder.count <= 1 && groups[nextIndex].count == 1 ? groups[nextIndex][0].id : nil,
            markAsViewed: !showUnreviewedOnly,
            preserveFolderSlots: true
        )
        return true
    }

    @discardableResult
    public func stepSingleImageViewer(delta: Int) -> Bool {
        guard isSingleImageCompareMode,
              let currentID = compareSelectionIDs.first ?? selectedAssetID,
              let nextAsset = visibleSnapshot.asset(afterMovingFrom: currentID, delta: delta),
              nextAsset.id != currentID else {
            return false
        }

        enterCompareMode(
            forAssetIDs: [nextAsset.id],
            focusedAssetID: nextAsset.id,
            markAsViewed: !showUnreviewedOnly
        )
        return true
    }

    public func exitCompareMode() {
        let fallbackSelection = compareFocusedAsset?.id ?? compareSelectionIDs.first ?? selectedAssetIDs.sorted(by: assetOrder).first
        compareSession = CompareSessionState()
        mode = .grid
        rebuildVisibleSnapshot()
        selection.select(fallbackSelection)
    }

    public func focusCompareAsset(_ assetID: UUID) {
        guard compareSelectionIDs.contains(assetID) else { return }
        updateCompareSession { compareCoordinator.focus(assetID, in: &$0) }
        selection.focusedAssetID = assetID
        markCompareGroupsViewed(for: [assetID])
        scheduleMetadataLoad(for: compareSelectionIDs)
    }

    public func showCompareOverview() {
        updateCompareSession { compareCoordinator.showOverview(in: &$0) }
        selection.focusedAssetID = compareSelectionIDs.first
        scheduleMetadataLoad(for: compareSelectionIDs)
    }

    public func toggleCompareOverlay(slot: Int) {
        guard let asset = compareAsset(atPane: slot - 1),
              let selectionIndex = compareSelectionIDs.firstIndex(of: asset.id) else { return }
        var loadedAssetID: UUID?
        updateCompareSession {
            loadedAssetID = compareCoordinator.toggleOverlay(slot: selectionIndex + 1, in: &$0)
        }
        if let loadedAssetID {
            scheduleMetadataLoad(for: [loadedAssetID])
        }
    }

    public func setBaseCompareOverlay(slot: Int) {
        guard let asset = compareAsset(atPane: slot - 1),
              let selectionIndex = compareSelectionIDs.firstIndex(of: asset.id) else { return }
        var result: (baseID: UUID, overlayID: UUID)?
        updateCompareSession {
            result = compareCoordinator.setBaseOverlay(slot: selectionIndex + 1, in: &$0)
        }
        guard let result else { return }
        selection.focusedAssetID = result.baseID
        markCompareGroupsViewed(for: result.overlayID == result.baseID ? [result.baseID] : [result.baseID, result.overlayID])
        scheduleMetadataLoad(for: result.overlayID == result.baseID ? [result.baseID] : [result.baseID, result.overlayID])
    }

    public func cyclicOverlayAssetID(forAssetAt index: Int) -> UUID? {
        let panes = comparePaneAssets
        guard panes.count >= 2, panes.indices.contains(index), panes[index] != nil else { return nil }
        return panes[(index + 1) % panes.count]?.id
    }

    public func beginTemporaryOverlay(slot: Int) {
        var overlaySlot: Int?
        updateCompareSession {
            overlaySlot = compareCoordinator.beginTemporaryOverlay(slot: slot, in: &$0)
        }
        if let overlaySlot, overlayCompareCandidates.indices.contains(overlaySlot) {
            let overlayID = overlayCompareCandidates[overlaySlot].id
            if !isShowingCompareOverview {
                markCompareGroupsViewed(for: [overlayID])
            }
            scheduleMetadataLoad(for: [overlayID])
        }
    }

    public func endTemporaryOverlay() {
        updateCompareSession { compareCoordinator.endTemporaryOverlay(in: &$0) }
    }

    public func toggleOverlayAB() {
        var slot: Int?
        updateCompareSession {
            slot = compareCoordinator.toggleTemporaryOverlay(in: &$0)
        }
        if let slot {
            let overlayID = overlayCompareCandidates[slot].id
            if !isShowingCompareOverview {
                markCompareGroupsViewed(for: [overlayID])
            }
            scheduleMetadataLoad(for: [overlayID])
        }
    }

    public func applyRating(_ rating: RatingState, to assetIDs: [UUID]) {
        mutateDecisionRecords(assetIDs) { $0.ratingState = rating }
    }

    public func applyRatingToFocusedSelection(_ rating: RatingState) {
        let target = focusedAssetIDs
        guard !target.isEmpty else { return }
        applyRating(rating, to: target)
    }

    public func rotateAssets(_ assetIDs: [UUID], quarterTurns: Int = 1) {
        guard quarterTurns != 0 else { return }
        mutateDecisionRecords(assetIDs) { asset in
            asset.rotationDegrees = AssetRecord.normalizedRotationDegrees(
                asset.rotationDegrees + ((quarterTurns % 4) * 90)
            )
        }
    }

    public func rotateFocusedAsset(quarterTurns: Int = 1) {
        let target = compareFocusedAsset?.id ?? selectedAssetID
        guard let target else { return }
        rotateAssets([target], quarterTurns: quarterTurns)
    }

    public func rotateCompareSelection(quarterTurns: Int = 1) {
        let target = compareSelectionIDs
        if target.isEmpty {
            rotateFocusedAsset(quarterTurns: quarterTurns)
        } else {
            rotateAssets(target, quarterTurns: quarterTurns)
        }
    }

    public func rotateLocalAssetFiles(_ assetIDs: [UUID], quarterTurns: Int = 1) async {
        let normalizedTurns = ((quarterTurns % 4) + 4) % 4
        guard normalizedTurns != 0 else { return }
        let idSet = Set(assetIDs)
        await fileMutationGate.acquire(idSet)
        defer { fileMutationGate.release(idSet) }
        guard !Task.isCancelled else { return }
        let operations = assets.compactMap { asset -> AssetFileRotationOperation? in
            guard idSet.contains(asset.id), let fileURL = fileURL(for: asset) else { return nil }
            return AssetFileRotationOperation(
                assetID: asset.id,
                fileURL: fileURL,
                finderTags: asset.finderTagSyncIssue == nil ? asset.finderTags : []
            )
        }
        guard !operations.isEmpty else { return }

        noteLocalFileMutation()
        rotationErrorMessage = nil
        activeRotationOperations += 1
        isRotatingLocalFiles = true
        defer {
            activeRotationOperations -= 1
            isRotatingLocalFiles = activeRotationOperations > 0
        }
        let rotationService = assetFileRotationService
        let tagService = finderTagService

        do {
            try await Task.detached(priority: .userInitiated) {
                let backup = try FileMutationBackup(urls: operations.map(\.fileURL))
                do {
                    for operation in operations {
                        try rotationService.rotateFile(at: operation.fileURL, quarterTurns: normalizedTurns)
                        if !operation.finderTags.isEmpty {
                            try tagService.writeTags(operation.finderTags, at: operation.fileURL)
                        }
                    }
                } catch {
                    do { try backup.restore() } catch {
                        throw AssetFileRotationError.rollbackFailed(recoveryDirectory: backup.recoveryDirectory, detail: error.localizedDescription)
                    }
                    backup.discard()
                    throw error
                }
                backup.discard()
            }.value

            let urlsByID = Dictionary(uniqueKeysWithValues: operations.map { ($0.assetID, $0.fileURL) })
            let fileValues = await Task.detached(priority: .userInitiated) {
                urlsByID.compactMapValues { url -> (fileSize: Int?, contentModificationDate: Date?)? in
                    guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
                    return (values.fileSize, values.contentModificationDate)
                }
            }.value
                assets = assets.map { asset in
                    guard idSet.contains(asset.id) else { return asset }
                    var updated = asset
                    if normalizedTurns % 2 == 1, asset.hasKnownDimensions {
                        swap(&updated.width, &updated.height)
                    }
                    if let values = fileValues[asset.id] {
                        updated.fileSizeBytes = Int64(values.fileSize ?? Int(asset.fileSizeBytes))
                        updated.contentModificationDate = values.contentModificationDate ?? Date()
                    }
                    return updated
                }
                rebuildDerivedCaches()
            invalidateImages(for: idSet)
        } catch {
            rotationErrorMessage = error.localizedDescription
        }
    }

    public func dismissRotationError() {
        rotationErrorMessage = nil
    }

    public func imageRefreshToken(for assetID: UUID) -> UUID {
        assetImageRefreshTokens[assetID] ?? imageRefreshToken
    }

    private func invalidateImages(for assetIDs: Set<UUID>) {
        guard !assetIDs.isEmpty else { return }
        var updatedTokens = assetImageRefreshTokens
        for assetID in assetIDs {
            updatedTokens[assetID] = UUID()
        }
        assetImageRefreshTokens = updatedTokens
    }

    private func invalidateAllImages() {
        assetImageRefreshTokens = [:]
        imageRefreshToken = UUID()
    }

    private var isGlobalImageRefreshSuppressed: Bool {
        Date() < suppressGlobalImageRefreshUntil
    }

    private func noteLocalFileMutation() {
        suppressGlobalImageRefreshUntil = Date().addingTimeInterval(localFileMutationRefreshSuppressionInterval)
    }

    public func moveSelection(delta: Int, extend: Bool = false) {
        guard let nextAsset = visibleSnapshot.asset(afterMovingFrom: selectedAssetID, delta: delta) else { return }
        let nextID = nextAsset.id

        if extend {
            toggleSelection(assetID: nextID)
            selection.focusedAssetID = nextID
            scheduleMetadataLoad(for: [nextID])
        } else {
            select(assetID: nextID)
        }
    }

    public func visibleAssetID(after assetID: UUID, delta: Int = 1) -> UUID? {
        visibleSnapshot.asset(afterMovingFrom: assetID, delta: delta)?.id
    }

    public func jumpSelectionToEdge(end: Bool) {
        guard let target = end ? visibleSnapshot.lastAsset : visibleSnapshot.firstAsset else { return }
        select(assetID: target.id)
    }

    /// Export follows the sidebar's directory selection. Review/search/category
    /// filters only affect browsing; the export dialog chooses the classifications.
    private var exportScopeAssets: [AssetRecord] {
        let folders = exportScopeFolderPaths
        return assets.filter { asset in
            (selectedLibraryID == nil || asset.libraryID == selectedLibraryID)
                && (folders.isEmpty || folders.contains { assetMatchesFolder(asset, folderPath: $0) })
        }
    }

    private var exportScopeFolderPaths: [String] {
        let folders = selectedFolderPaths.isEmpty
            ? Set(selectedFolderPath.map { [$0] } ?? [])
            : selectedFolderPaths
        let orderedFolders = selectedFolderOrder.filter { folders.contains($0) }
        return orderedFolders + folders.subtracting(orderedFolders).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    public var exportScopeDescription: String {
        let folders = exportScopeFolderPaths
        let libraryName = libraries.first { $0.id == selectedLibraryID }?.displayName
        if !folders.isEmpty {
            return [libraryName, folders.joined(separator: "、")].compactMap { $0 }.joined(separator: " / ")
        }
        return libraryName.map { "\($0) / 全部子目录" } ?? "全部素材目录"
    }

    public var exportScopeSummary: AssetCategorySummary {
        if let cachedExportScopeSummary {
            return cachedExportScopeSummary
        }

        let scopedAssets = exportScopeAssets
        var keepCount = 0
        var rejectCount = 0
        var pendingCount = 0
        var prioritySummary = PriorityTagSummary()
        var finderTagCounts: [FinderTagColor: Int] = [:]

        for asset in scopedAssets {
            switch asset.ratingState {
            case .keep: keepCount += 1
            case .reject: rejectCount += 1
            case .pending: pendingCount += 1
            }
            prioritySummary.record(asset.priorityTag)
            for color in Set(asset.finderTags.map(\.color)) {
                finderTagCounts[color, default: 0] += 1
            }
        }

        let summary = AssetCategorySummary(
            totalCount: scopedAssets.count,
            keepCount: keepCount,
            rejectCount: rejectCount,
            pendingCount: pendingCount,
            priorityTagSummary: prioritySummary,
            finderTagColorSummary: FinderTagColorSummary(counts: finderTagCounts)
        )
        cachedExportScopeSummary = summary
        return summary
    }

    public func exportDecisions(
        keepFolderPath: String? = nil,
        rejectFolderPath: String? = nil,
        pendingFolderPath: String? = nil,
        priorityTagFolderPaths: [PriorityTag: String] = [:],
        finderTagFolderPaths: [FinderTagColor: String] = [:],
        includeKeep: Bool = true,
        includeReject: Bool = true,
        includePending: Bool = false,
        includedPriorityTags: Set<PriorityTag> = [],
        includedFinderTagColors: Set<FinderTagColor> = []
    ) async throws -> ExportExecutionSummary {
        exportProgress = ExportProgress(completed: 0, total: 0)
        defer { exportProgress = nil }
        let resolvedKeepFolderPath = keepFolderPath ?? self.keepFolderPath
        let resolvedRejectFolderPath = rejectFolderPath ?? self.rejectFolderPath
        let resolvedPendingFolderPath = pendingFolderPath ?? defaultPendingExportFolderPath(
            keepFolderPath: resolvedKeepFolderPath,
            rejectFolderPath: resolvedRejectFolderPath
        )
        let exportAssets = exportScopeAssets.filter { asset in
            if let priorityTag = asset.priorityTag, includedPriorityTags.contains(priorityTag) {
                return true
            }
            if asset.finderTags.contains(where: { includedFinderTagColors.contains($0.color) }) {
                return true
            }

            switch asset.ratingState {
            case .keep:
                return includeKeep
            case .reject:
                return includeReject
            case .pending:
                return includePending
            }
        }

        return try await exportExecutor.export(
            ExportRequest(
                libraries: libraries,
                assets: exportAssets,
                keepFolderPath: resolvedKeepFolderPath,
                rejectFolderPath: resolvedRejectFolderPath,
                pendingFolderPath: resolvedPendingFolderPath,
                priorityTagFolderPaths: priorityTagFolderPaths,
                finderTagFolderPaths: finderTagFolderPaths,
                includeKeep: includeKeep,
                includeReject: includeReject,
                includePending: includePending,
                includedPriorityTags: includedPriorityTags,
                includedFinderTagColors: includedFinderTagColors,
                onProgress: { [weak self] progress in
                    Task { @MainActor in self?.exportProgress = progress }
                }
            )
        )
    }

    private func defaultPendingExportFolderPath(keepFolderPath: String, rejectFolderPath: String) -> String {
        let referencePath = rejectFolderPath.isEmpty ? keepFolderPath : rejectFolderPath
        guard !referencePath.isEmpty else { return "未处理" }

        return URL(fileURLWithPath: referencePath, isDirectory: true)
            .deletingLastPathComponent()
            .appendingPathComponent("未处理", isDirectory: true)
            .path
    }

    public func appendTag(_ tagName: String, to assetIDs: [UUID]) {
        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        mutateDecisionRecords(assetIDs) { asset in
            if asset.appTags.contains(where: { $0.id == trimmed.lowercased() }) {
                return
            }
            asset.appTags.append(AppTag(name: trimmed))
        }
    }

    public func applyPriorityTag(_ priorityTag: PriorityTag, to assetIDs: [UUID]) {
        mutateDecisionRecords(assetIDs) { asset in
            asset.appTags.removeAll { PriorityTag.fromAppTag($0) != nil }
            asset.ratingState = .reject
            asset.appTags.append(priorityTag.appTag)
        }
    }

    public func applyPriorityTagToFocusedSelection(_ priorityTag: PriorityTag) {
        let target = focusedAssetIDs
        guard !target.isEmpty else { return }
        applyPriorityTag(priorityTag, to: target)
    }

    public func clearPriorityTags(from assetIDs: [UUID]) {
        mutateDecisionRecords(assetIDs) { asset in
            asset.appTags.removeAll { PriorityTag.fromAppTag($0) != nil }
        }
    }

    public func clearPriorityTagsFromFocusedSelection() {
        let target = focusedAssetIDs
        guard !target.isEmpty else { return }
        clearPriorityTags(from: target)
    }

    public func clearAllTriageTags(from assetIDs: [UUID]) {
        mutateDecisionRecords(assetIDs) { asset in
            asset.ratingState = .pending
            asset.appTags.removeAll { PriorityTag.fromAppTag($0) != nil }
        }
    }

    public func clearAllTriageTagsFromFocusedSelection() {
        let target = focusedAssetIDs
        guard !target.isEmpty else { return }
        clearAllTriageTags(from: target)
    }

    public func clearAllTriageTagsFromWorkspace() {
        clearAllTriageTags(from: assets.map(\.id))
    }

    public func finderTagSelectionState(_ tag: FinderTag, for assetIDs: [UUID]) -> FinderTagSelectionState {
        let selectedAssets = assetIDs.compactMap(assetByID)
        guard !selectedAssets.isEmpty else { return .none }
        let matchingCount = selectedAssets.count { asset in
            asset.finderTags.contains { $0.matches(tag) }
        }
        if matchingCount == 0 { return .none }
        return matchingCount == selectedAssets.count ? .all : .mixed
    }

    public func toggleFinderTag(_ tag: FinderTag, for assetIDs: [UUID]) async {
        guard !tag.name.isEmpty else { return }
        let shouldRemove = finderTagSelectionState(tag, for: assetIDs) == .all
        await updateFinderTags(for: assetIDs) { existingTags in
            var updated = existingTags.filter { !$0.matches(tag) }
            if !shouldRemove {
                updated.append(tag)
            }
            return FinderTag.normalized(updated)
        }
    }

    public func toggleFinderTagForCompareGroup(_ tag: FinderTag) async {
        await toggleFinderTag(tag, for: compareSelectionIDs)
    }

    public func replaceFinderTagsForCompareGroup(with tags: [FinderTag]) async {
        await replaceFinderTags(with: tags, for: compareSelectionIDs)
    }

    public func toggleExclusiveFinderTagForCompareGroup(_ tag: FinderTag) async {
        await toggleExclusiveFinderTag(tag, for: compareSelectionIDs)
    }

    public func clearFinderTagsForCompareGroup() async {
        await clearFinderTags(for: compareSelectionIDs)
    }

    public func applyFinderTag(_ tag: FinderTag, for assetIDs: [UUID]) async {
        guard !tag.name.isEmpty else { return }
        await updateFinderTags(for: assetIDs) { existingTags in
            FinderTag.normalized(existingTags.filter { !$0.matches(tag) } + [tag])
        }
    }

    public func replaceFinderTags(with tags: [FinderTag], for assetIDs: [UUID]) async {
        let normalizedTags = FinderTag.normalized(tags)
        await updateFinderTags(for: assetIDs) { _ in normalizedTags }
    }

    public func toggleExclusiveFinderTag(_ tag: FinderTag, for assetIDs: [UUID]) async {
        guard !tag.name.isEmpty else { return }
        await updateFinderTags(for: assetIDs, exclusiveToggle: tag) { $0 }
    }

    public func clearFinderTags(for assetIDs: [UUID]) async {
        await updateFinderTags(for: assetIDs) { _ in [] }
    }

    public func dismissFinderTagError() {
        finderTagErrorMessage = nil
    }

    /// Only retries files in the current workspace, never unrelated saved paths.
    public func retryPendingFinderTags() async {
        await updateFinderTags(
            for: assets.filter { $0.finderTagSyncIssue != nil }.map(\.id),
            retryPending: true
        ) { $0 }
    }

    public func refreshFinderTagsFromDisk() async {
        let lockedIDs = Set(assets.map(\.id))
        await fileMutationGate.acquire(lockedIDs)
        defer { fileMutationGate.release(lockedIDs) }
        let targets = assets.compactMap { asset -> FinderTagReadTarget? in
            guard asset.finderTagSyncIssue == nil, let fileURL = fileURL(for: asset) else { return nil }
            return FinderTagReadTarget(assetID: asset.id, fileURL: fileURL)
        }
        guard !targets.isEmpty else { return }

        let service = finderTagService
        let tagsByAssetID = await Task.detached(priority: .utility) {
            var result: [UUID: [FinderTag]] = [:]
            for start in stride(from: 0, to: targets.count, by: 16) {
                await withTaskGroup(of: (UUID, [FinderTag]?).self) { group in
                    for target in targets[start..<min(start + 16, targets.count)] {
                        group.addTask { (target.assetID, try? service.readTags(at: target.fileURL)) }
                    }
                    for await (id, tags) in group { if let tags { result[id] = tags } }
                }
            }
            return result
        }.value

        var didChange = false
        assets = assets.map { asset in
            guard let tags = tagsByAssetID[asset.id], tags != asset.finderTags else { return asset }
            var updated = asset
            updated.finderTags = tags
            didChange = true
            return updated
        }
        if didChange {
            rebuildDerivedCaches()
        }
    }

    private func updateFinderTags(
        for assetIDs: [UUID],
        exclusiveToggle: FinderTag? = nil,
        retryPending: Bool = false,
        transform: ([FinderTag]) -> [FinderTag]
    ) async {
        let idSet = Set(assetIDs)
        await fileMutationGate.acquire(idSet)
        defer { fileMutationGate.release(idSet) }
        guard !Task.isCancelled else { return }
        let toggledTags = exclusiveToggle.map { tag in
            finderTagSelectionState(tag, for: assetIDs) == .all ? [] : [tag]
        }
        let operations = assets.compactMap { asset -> FinderTagWriteOperation? in
            guard idSet.contains(asset.id), let fileURL = fileURL(for: asset) else { return nil }
            let updatedTags = toggledTags ?? transform(asset.finderTags)
            guard updatedTags != asset.finderTags || (retryPending && asset.finderTagSyncIssue != nil) else { return nil }
            return FinderTagWriteOperation(
                assetID: asset.id,
                fileURL: fileURL,
                updatedTags: updatedTags
            )
        }
        guard !operations.isEmpty else { return }

        noteLocalFileMutation()
        finderTagErrorMessage = nil
        activeTagOperations += 1
        isUpdatingFinderTags = true
        defer {
            activeTagOperations -= 1
            isUpdatingFinderTags = activeTagOperations > 0
        }
        let service = finderTagService
        let store = pendingFinderTagStore
        let previousPending = pendingFinderTagEdits

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                // Write ahead: an interruption must not lose a color change or
                // resurrect an older pending edit after a successful Finder write.
                var staged: [String: PendingFinderTagEdit] = [:]
                for operation in operations {
                    staged[PendingFinderTagKey.make(for: operation.fileURL)] = PendingFinderTagEdit(
                        tags: operation.updatedTags, reason: "尚未确认写入 Finder，可重试同步。"
                    )
                }
                try store.apply(updates: staged, removingKeys: [])
                var result = FinderTagBatchResult()
                for operation in operations {
                    let key = PendingFinderTagKey.make(for: operation.fileURL)
                    if let previous = previousPending[key], !retryPending {
                        result.pendingUpdates[key] = PendingFinderTagEdit(tags: operation.updatedTags, reason: previous.reason)
                        result.tagsByID[operation.assetID] = operation.updatedTags
                        continue
                    }
                    do {
                        try service.writeTags(operation.updatedTags, at: operation.fileURL)
                        result.tagsByID[operation.assetID] = operation.updatedTags
                        result.removedKeys.insert(key)
                    } catch {
                        if let reason = FinderTagWriteFailure.localFallbackReason(for: error) {
                            result.pendingUpdates[key] = PendingFinderTagEdit(tags: operation.updatedTags, reason: reason)
                            result.tagsByID[operation.assetID] = operation.updatedTags
                        } else {
                            // Missing files and unexpected I/O failures are not
                            // silently reported as successful tagging.
                            if let previous = previousPending[key] {
                                result.pendingUpdates[key] = previous
                            } else {
                                result.removedKeys.insert(key)
                            }
                            result.failures.append("\(operation.fileURL.lastPathComponent)：\(error.localizedDescription)")
                        }
                    }
                }
                do {
                    try store.apply(updates: result.pendingUpdates, removingKeys: result.removedKeys)
                } catch {
                    // The durable journal still contains the intended tags. Keep
                    // that exact state visible until cleanup can be retried.
                    result.pendingUpdates = staged
                    result.removedKeys = []
                    for operation in operations { result.tagsByID[operation.assetID] = operation.updatedTags }
                    result.failures.append("标签已记入本机记录，但同步状态保存失败，请重试：\(error.localizedDescription)")
                }
                return result
            }.value

            for key in result.removedKeys { pendingFinderTagEdits.removeValue(forKey: key) }
            pendingFinderTagEdits.merge(result.pendingUpdates) { _, new in new }
            assets = assets.map { asset in
                guard let tags = result.tagsByID[asset.id], let url = fileURL(for: asset) else { return asset }
                var updated = asset
                updated.finderTags = tags
                updated.finderTagSyncIssue = pendingFinderTagEdits[PendingFinderTagKey.make(for: url)]?.reason
                return updated
            }
            rebuildDerivedCaches()
            if !result.failures.isEmpty {
                finderTagErrorMessage = "\(result.failures.count) 项未能正常同步；其他图片不受影响。\n" + result.failures.prefix(3).joined(separator: "\n")
            }
        } catch {
            finderTagErrorMessage = "本机标签记录保存失败，本次未修改图片标签。请检查本机可用空间与权限。\n\(error.localizedDescription)"
        }
    }

    public func revealSelectedAssetInFinder() {
        guard let url = selectedAssetFileURL else { return }
        inspectionService.revealInFinder(url)
    }

    public func revealAssetInFinder(_ asset: AssetRecord) {
        guard let url = fileURL(for: asset) else { return }
        inspectionService.revealInFinder(url)
    }

    public func fileURL(for asset: AssetRecord) -> URL? {
        guard let libraryPath = libraryPathByID[asset.libraryID] else {
            return nil
        }

        return URL(fileURLWithPath: libraryPath)
            .appendingPathComponent(asset.relativePath)
    }

    public func revealKeepExportFolder() {
        inspectionService.revealInFinder(URL(fileURLWithPath: keepFolderPath))
    }

    public func revealRejectExportFolder() {
        inspectionService.revealInFinder(URL(fileURLWithPath: rejectFolderPath))
    }

    public func revealFolder(at path: String) {
        inspectionService.revealInFinder(URL(fileURLWithPath: path, isDirectory: true))
    }

    public func revealExportFolders(for summary: ExportExecutionSummary) {
        if summary.keepCount > 0 {
            revealKeepExportFolder()
        }

        if summary.rejectCount > 0 {
            revealRejectExportFolder()
        }
    }

    public func quickLookSelectedAsset() {
        guard let url = selectedAssetFileURL else { return }
        inspectionService.quickLook(url)
    }

    public func deleteFocusedAssets() {
        let target = focusedAssetIDs
        guard !target.isEmpty else { return }

        let visibleBeforeDelete = visibleSnapshot.assetIDs
        let anchor = nextSelectionAnchor(beforeDeleting: target, within: visibleBeforeDelete)

        let deletedIDs = Set(target)
        assets.removeAll { deletedIDs.contains($0.id) }
        compareGroups = CompareGroupingService.buildGroups(libraries: libraries, assets: assets)
        rebuildDerivedCaches()
        updateCompareSession { compareCoordinator.removeSelectionIDs(Set(target), from: &$0) }

        if let anchor, assets.contains(where: { $0.id == anchor }) {
            select(assetID: anchor)
        } else if let first = visibleSnapshot.firstAsset {
            selection.focusedAssetID = first.id
        } else {
            clearSelection()
        }

        if compareSelectionIDs.isEmpty {
            exitCompareMode()
        } else {
            updateCompareSession { compareCoordinator.normalize(&$0) }
        }
    }

    public var focusedAssetIDs: [UUID] {
        if mode == .compare {
            if let focused = compareFocusedAsset?.id { return [focused] }
            return []
        }

        if !selectedAssetIDs.isEmpty {
            return selectedAssetIDs.sorted(by: assetOrder)
        }

        if let selectedAssetID { return [selectedAssetID] }
        return []
    }

    public func libraryAssetCount(_ libraryID: UUID) -> Int {
        libraryAssetCountCache[libraryID] ?? 0
    }

    private func assetByID(_ id: UUID) -> AssetRecord? {
        assetIndexByID[id]
    }

    private func enterCompareMode(forBasenameKey key: String, focusedAssetID: UUID? = nil) {
        if compareFolderOrder.count > 1 {
            let group = visibleCompareRows
                .first { row in row.contains { $0?.compareAlignmentKey == key } }
                .map { $0.compactMap(\.self) }
                ?? filteredAssets.first { $0.compareAlignmentKey == key }.map { [$0] }
                ?? []
            guard !group.isEmpty else { return }
            enterCompareMode(forAssetIDs: group.map(\.id), focusedAssetID: focusedAssetID, preserveFolderSlots: true)
            return
        }

        let group = viewerCompareGroups
            .first { group in group.contains { $0.compareAlignmentKey == key } }
            ?? filteredAssets.first { $0.compareAlignmentKey == key }.map { [$0] }
            ?? []
        guard !group.isEmpty else { return }
        enterCompareMode(forAssetIDs: group.map(\.id), focusedAssetID: focusedAssetID)
    }

    private func enterCompareMode(
        forAssetIDs assetIDs: [UUID],
        focusedAssetID: UUID?,
        markAsViewed: Bool = true,
        preserveFolderSlots: Bool = false
    ) {
        let ordered = compareOrderedAssetIDs(assetIDs)
        guard !ordered.isEmpty else { return }
        compareSession = compareCoordinator.makeSession(selectionIDs: ordered, focusedAssetID: focusedAssetID)
        if preserveFolderSlots, compareFolderOrder.count > 1 {
            compareSession.folderPaths = compareFolderOrder
        }
        selection.focusedAssetID = focusedAssetID ?? ordered.first
        selection.setOrdered(ordered)
        mode = .compare
        // Pinning the new group only affects a filtered view. Normal browsing
        // must not rebuild/sort the entire workspace for every next-group key.
        if categoryFilter != .all || showUnreviewedOnly { rebuildVisibleSnapshot() }
        if markAsViewed && !showUnreviewedOnly {
            markCompareGroupsViewed(for: ordered)
        }
        scheduleMetadataLoad(for: ordered)
    }

    private func compareOrderedAssetIDs(_ assetIDs: some Sequence<UUID>) -> [UUID] {
        if compareFolderOrder.count > 1 {
            return assetIDs.sorted(by: assetOrder)
        }

        return AssetFilenameSortKey.sorted(assetIDs.compactMap(assetByID)).map(\.id)
    }

    private func basenameKey(for filename: String) -> String {
        VisibleAssetSnapshot.basenameKey(for: filename)
    }

    private func effectiveCompareFolderOrder() -> [String] {
        if selectedFolderOrder.count > 1 {
            return selectedFolderOrder
        }

        guard selectedFolderOrder.isEmpty,
              selectedFolderPaths.isEmpty,
              selectedFolderPath == nil,
              selectedLibraryID != nil || libraries.count == 1 else {
            return []
        }

        let topLevelFolders = filteredAssets.compactMap { topLevelFolderPath(for: $0.relativePath) }
        let uniqueFolders = Array(Set(topLevelFolders)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        return uniqueFolders.count > 1 ? uniqueFolders : []
    }

    private var filteredComparison: FolderComparisonSnapshot {
        if let cachedFilteredComparison { return cachedFilteredComparison }
        let result = FolderComparisonSnapshot(
            rows: pairedCompareRowsForSelectedFolders(using: filteredAssets), folderOrder: compareFolderOrder
        )
        cachedFilteredComparison = result
        return result
    }

    private var scopedComparison: FolderComparisonSnapshot {
        if let cachedScopedComparison { return cachedScopedComparison }
        let result = FolderComparisonSnapshot(
            rows: pairedCompareRowsForSelectedFolders(using: visibleSnapshot.scopedAssets), folderOrder: compareFolderOrder
        )
        cachedScopedComparison = result
        return result
    }

    /// Builds comparison rows in two deterministic passes. Filename matches always win;
    /// only the remaining assets can consume a cached thumbnail-content match.
    private func pairedCompareRowsForSelectedFolders(using sourceAssets: [AssetRecord]) -> [[AssetRecord?]] {
        let folderOrder = compareFolderOrder
        guard folderOrder.count > 1 else { return [] }

        let columns = folderOrder.map { folderPath in
            sourceAssets.filter { assetMatchesFolder($0, folderPath: folderPath) }
        }
        guard let referenceColumn = columns.first else { return [] }

        var rows = referenceColumn.map { referenceAsset -> [AssetRecord?] in
            var row = Array<AssetRecord?>(repeating: nil, count: folderOrder.count)
            row[0] = referenceAsset
            return row
        }

        for folderIndex in 1..<folderOrder.count {
            let targetFolderPath = folderOrder[folderIndex]
            let targetColumn = columns[folderIndex]
            let filenameMatches = FilenameMatchingService.match(
                referenceRows: rows.map { $0.compactMap(\.self) }, targets: targetColumn
            )
            var usedTargetIDs = Set(filenameMatches.values.map(\.id))

            // Filename pass: full stems first, then stems without _x / _xx suffixes.
            for (rowIndex, match) in filenameMatches {
                rows[rowIndex][folderIndex] = match
            }

            // Pass 2: cached low-resolution visual fingerprint matches.
            let targetAssetByID = Dictionary(uniqueKeysWithValues: targetColumn.map { ($0.id, $0) })
            for rowIndex in rows.indices {
                guard rows[rowIndex][folderIndex] == nil,
                      let referenceAsset = rows[rowIndex].compactMap({ $0 }).first,
                      let targetAssetID = contentMatchedAssetIDByKey[
                        ContentMatchKey(
                            referenceAssetID: referenceAsset.id,
                            targetFolderPath: targetFolderPath
                        )
                      ],
                      !usedTargetIDs.contains(targetAssetID),
                      let match = targetAssetByID[targetAssetID] else {
                    continue
                }
                rows[rowIndex][folderIndex] = match
                usedTargetIDs.insert(match.id)
            }

            rows = CompareRowInsertionService.inserting(
                targetColumn.filter { !usedTargetIDs.contains($0.id) },
                into: rows, column: folderIndex, columnCount: folderOrder.count
            )
        }

        return isMatchingImageContent ? rows.filter { $0[0] != nil } : rows
    }

    private func contentMatchingPlans(
        folderOrder: [String],
        sourceAssets: [AssetRecord]
    ) -> [ContentMatchingColumnPlan] {
        let columns = folderOrder.map { folderPath in
            sourceAssets.filter { assetMatchesFolder($0, folderPath: folderPath) }
        }
        guard let firstColumn = columns.first else { return [] }
        // Keep every filename alias in its row, exactly as the displayed pairing
        // does. Otherwise a suffix match can reserve a target for a different row
        // here and leave the actual unmatched row out of thumbnail detection.
        var referenceRows = firstColumn.map { [$0] }
        var plans: [ContentMatchingColumnPlan] = []
        for folderIndex in 1..<folderOrder.count {
            let targetColumn = columns[folderIndex]
            let filenameMatches = FilenameMatchingService.match(
                referenceRows: referenceRows, targets: targetColumn
            )
            let matchedTargetIDs = Set(filenameMatches.values.map(\.id))

            let unmatchedReferenceIDs = referenceRows.enumerated().compactMap { rowIndex, row in
                filenameMatches[rowIndex] == nil ? row.first?.id : nil
            }
            let unmatchedTargetIDs = targetColumn
                .filter { !matchedTargetIDs.contains($0.id) }
                .map(\.id)
            if !unmatchedReferenceIDs.isEmpty, !unmatchedTargetIDs.isEmpty {
                plans.append(ContentMatchingColumnPlan(
                    targetFolderPath: folderOrder[folderIndex],
                    referenceAssetIDs: unmatchedReferenceIDs,
                    targetAssetIDs: unmatchedTargetIDs
                ))
            }
            for (rowIndex, target) in filenameMatches {
                referenceRows[rowIndex].append(target)
            }
            referenceRows.append(contentsOf: targetColumn
                .filter { !matchedTargetIDs.contains($0.id) }.map { [$0] })
        }
        return plans
    }

    private func topLevelFolderPath(for relativePath: String) -> String? {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count > 1,
              let first = components.first else {
            return nil
        }
        return String(first)
    }

    private func assetMatchesFolder(_ asset: AssetRecord, folderPath: String) -> Bool {
        asset.relativePath == folderPath || asset.relativePath.hasPrefix(folderPath + "/")
    }

    private var overlayCompareCandidates: [AssetRecord] {
        compareAssets.filter { $0.id != compareFocusedAsset?.id }
    }

    private func normalizedDirectoryPath(for url: URL) -> String? {
        guard url.isFileURL else { return nil }

        let normalizedURL = url.standardizedFileURL
        let values = try? normalizedURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else { return nil }
        return normalizedURL.path
    }

    private var selectedAssetFileURL: URL? {
        guard let asset = selectedAsset else { return nil }
        return fileURL(for: asset)
    }

    private func assetOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        (visibleSnapshot.index(of: lhs) ?? .max) < (visibleSnapshot.index(of: rhs) ?? .max)
    }

    private func idsSortedByAssetOrder(_ ids: some Sequence<UUID>) -> [UUID] {
        ids.sorted {
            assetArrayIndexByID[$0, default: .max] < assetArrayIndexByID[$1, default: .max]
        }
    }

    private func updateCompareSession(_ mutate: (inout CompareSessionState) -> Void) {
        var session = compareSession
        mutate(&session)
        compareSession = session
    }

    /// Decisions change payloads, never file identity or comparison alignment.
    /// Do not rebuild folder trees, filename indexes or thumbnail-match plans on
    /// every key press. Those are rebuilt only when workspace contents change.
    private func mutateDecisionRecords(_ ids: [UUID], transform: (inout AssetRecord) -> Void) {
        var updates: [UUID: AssetRecord] = [:]
        for id in Set(ids) {
            guard let previous = assetIndexByID[id] else { continue }
            var next = previous
            transform(&next)
            guard next != previous else { continue }
            updates[id] = next
            let wasTagged = previous.ratingState != .pending || previous.priorityTag != nil
            let isTagged = next.ratingState != .pending || next.priorityTag != nil
            triageTaggedAssetCount += (isTagged ? 1 : 0) - (wasTagged ? 1 : 0)
            if let tag = previous.priorityTag {
                let count = cachedPriorityTagSummary.count(for: tag) - 1
                cachedPriorityTagSummary.counts[tag] = count > 0 ? count : nil
            }
            cachedPriorityTagSummary.record(next.priorityTag)
            if let libraryPath = libraryPathByID[next.libraryID] {
                let key = AssetDecisionKey.make(libraryPath: libraryPath, asset: next)
                currentDecisionSnapshot[key] = Self.persistedDecision(for: next)
            }
        }
        guard !updates.isEmpty else { return }
        var nextAssets = assets
        for (id, next) in updates {
            if let index = assetArrayIndexByID[id] { nextAssets[index] = next }
            assetIndexByID[id] = next
        }
        assets = nextAssets
        cachedHasAnyTriageTags = triageTaggedAssetCount > 0
        cachedExportScopeSummary = nil
        let unknownTags = Set(updates.values.compactMap(\.priorityTag)).subtracting(priorityTags)
        if !unknownTags.isEmpty {
            priorityTagDefinitions = (priorityTagDefinitions + unknownTags.map { PriorityTagDefinition(tag: $0) })
                .sorted { $0.tag < $1.tag }
        }
        var updatedGroups = compareGroups
        for groupIndex in Set(updates.keys.compactMap { comparisonGroupIndexByAssetID[$0] }) {
            for slotIndex in updatedGroups[groupIndex].slots.indices {
                if let id = updatedGroups[groupIndex].slots[slotIndex].asset?.id, let next = updates[id] {
                    updatedGroups[groupIndex].slots[slotIndex].asset = next
                }
            }
        }
        compareGroups = updatedGroups
        refreshComparisonPayloads(updates)
        let previousVisibleIDs = visibleSnapshot.assetIDs
        var nextVisible = visibleSnapshot
        // A manually chosen comparison can enter without rebuilding the query;
        // pin its live selection before filtering a changed rating/P label.
        nextVisible.query.pinnedAssetIDs = mode == .compare ? Set(compareSelectionIDs) : []
        if nextVisible.updateDecisionRecords(updates) {
            visibleSnapshot = nextVisible
            if previousVisibleIDs != nextVisible.assetIDs { invalidateCompareGroupsCache() }
        } else {
            rebuildVisibleSnapshot()
        }
        savedDecisionSnapshot = currentDecisionSnapshot
        decisionStore.saveDecisions(currentDecisionSnapshot)
        normalizeSelectionAfterMutation()
    }

    private func refreshComparisonPayloads(_ updates: [UUID: AssetRecord]) {
        func refresh(_ records: [AssetRecord]) -> [AssetRecord] { records.map { updates[$0.id] ?? $0 } }
        cachedBasenameCompareGroups = cachedBasenameCompareGroups.map { $0.map(refresh) }
        cachedFilteredComparison?.refreshPayloads(updates)
        cachedScopedComparison?.refreshPayloads(updates)
    }

    private func normalizeSelectionAfterMutation() {
        selection.normalize(existingIDs: Set(assetIndexByID.keys), fallbackFocusedID: visibleSnapshot.firstAsset?.id)
        updateCompareSession { session in
            session.selectionIDs = session.selectionIDs.filter { assetIndexByID[$0] != nil }
            compareCoordinator.normalize(&session)
        }
        if let selectedAssetID, assetIndexByID[selectedAssetID] == nil {
            selection.focusedAssetID = nil
        }
    }

    private func normalizeSelectionForVisibleAssets() {
        normalizeSelectionForVisibleAssets(preferredKeys: [], focusedKey: nil)
    }

    private func normalizeSelectionForVisibleAssets(
        preferredKeys: [AssetSelectionKey],
        focusedKey: AssetSelectionKey?
    ) {
        let visibleIDsByKey = Dictionary(uniqueKeysWithValues: filteredAssets.compactMap { asset in
            assetSelectionKey(for: asset).map { ($0, asset.id) }
        })

        let restoredSelectionIDs = preferredKeys.compactMap { visibleIDsByKey[$0] }
        if !restoredSelectionIDs.isEmpty {
            selection.setOrdered(restoredSelectionIDs)
        }

        if let focusedKey,
           let focusedID = visibleIDsByKey[focusedKey] {
            selection.focusedAssetID = focusedID
        } else if let focusedAssetID = selection.focusedAssetID,
                  visibleSnapshot.contains(focusedAssetID) {
            selection.focusedAssetID = focusedAssetID
        } else if let firstRestoredID = restoredSelectionIDs.first {
            selection.focusedAssetID = firstRestoredID
        }

        if let selectedAssetID, visibleSnapshot.contains(selectedAssetID) {
            selection.normalize(
                existingIDs: Set(assetIndexByID.keys),
                visibleIDs: visibleSnapshot.assetIDSet,
                fallbackFocusedID: selectedAssetID
            )
            scheduleMetadataLoad(for: Array(selection.assetIDs))
            return
        }

        if let focused = selection.focusedAssetID, visibleSnapshot.contains(focused) {
            scheduleMetadataLoad(for: Array(selection.assetIDs))
            return
        }

        clearSelection()
    }

    private func nextSelectionAnchor(beforeDeleting target: [UUID], within visibleIDs: [UUID]) -> UUID? {
        guard let currentID = selectedAssetID ?? focusedAssetIDs.first,
              let index = visibleIDs.firstIndex(of: currentID) else {
            return visibleIDs.first(where: { !target.contains($0) })
        }

        let trailing = visibleIDs.dropFirst(index + 1).first(where: { !target.contains($0) })
        if showUnreviewedOnly { return trailing }
        return trailing ?? visibleIDs[..<index].last(where: { !target.contains($0) })
    }

    private func rebuildDerivedCaches() {
        cachedKnownFinderTags = nil
        cachedFinderTagColorSummary = nil
        pendingFinderTagCount = assets.count { $0.finderTagSyncIssue != nil }
        assetIndexByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        assetArrayIndexByID = Dictionary(uniqueKeysWithValues: assets.enumerated().map { ($1.id, $0) })
        comparisonGroupIndexByAssetID = [:]
        for (index, group) in compareGroups.enumerated() {
            for slot in group.slots {
                if let id = slot.asset?.id { comparisonGroupIndexByAssetID[id] = index }
            }
        }
        libraryPathByID = Dictionary(uniqueKeysWithValues: libraries.map { ($0.id, $0.path) })
        metadataLoadingAssetIDs = metadataLoadingAssetIDs.intersection(Set(assetIndexByID.keys))
        viewedCompareGroupKeys = viewedCompareGroupKeys.intersection(Set(assets.map(\.compareAlignmentKey)))

        var assetsByLibraryID: [UUID: [AssetRecord]] = [:]
        assetsByLibraryID.reserveCapacity(libraries.count)
        for asset in assets {
            assetsByLibraryID[asset.libraryID, default: []].append(asset)
        }

        libraryAssetCountCache = assetsByLibraryID.mapValues(\.count)
        folderTreeCache = Dictionary(uniqueKeysWithValues: libraries.map { library in
            let libraryAssets = assetsByLibraryID[library.id, default: []]
            return (library.id, makeFolderTree(for: libraryAssets, libraryID: library.id))
        })
        rebuildAssetSummaryCaches()
        rebuildVisibleSnapshot()
        currentDecisionSnapshot = makeCurrentDecisionSnapshot()
    }

    private func rebuildAssetSummaryCaches() {
        cachedHasAnyTriageTags = false
        triageTaggedAssetCount = 0
        var prioritySummary = PriorityTagSummary()

        for asset in assets {
            if asset.ratingState != .pending || asset.priorityTag != nil {
                cachedHasAnyTriageTags = true
                triageTaggedAssetCount += 1
            }
            prioritySummary.record(asset.priorityTag)
        }

        cachedPriorityTagSummary = prioritySummary
        // Keep labels from existing decisions available even if their catalog came
        // from another installation or the preferences were reset.
        let knownTags = Set(priorityTags)
        let restoredTags = prioritySummary.counts.keys.filter { !knownTags.contains($0) }.sorted()
        if !restoredTags.isEmpty {
            priorityTagDefinitions = (priorityTagDefinitions + restoredTags.map { PriorityTagDefinition(tag: $0) })
                .sorted { $0.tag < $1.tag }
        }
    }

    private func rebuildVisibleSnapshot() {
        visibleSnapshot = VisibleAssetSnapshot(
            query: VisibleAssetQuery(
                searchText: searchText,
                selectedLibraryID: selectedLibraryID,
                selectedFolderPath: selectedFolderPath,
                selectedFolderPaths: selectedFolderPaths,
                selectedFolderOrder: selectedFolderOrder,
                showUnreviewedOnly: showUnreviewedOnly,
                viewedCompareGroupKeys: viewedCompareGroupKeys,
                categoryFilter: categoryFilter,
                sortMode: assetSortMode,
                pinnedAssetIDs: mode == .compare ? Set(compareSelectionIDs) : [],
                priorityTagNames: Dictionary(uniqueKeysWithValues: priorityTagDefinitions.map { ($0.tag, $0.name) })
            ),
            assets: assets,
            includeBasenameCompareGroups: false
        )
        invalidateCompareGroupsCache()
        cachedExportScopeSummary = nil
        scheduleContentMatchingForSelectedFolders()
    }

    private func invalidateCompareGroupsCache() {
        cachedCompareFolderOrder = nil
        cachedCompareGroupSize = nil
        cachedBasenameCompareGroups = nil
        cachedFilteredComparison = nil
        cachedScopedComparison = nil
        cachedEffectiveCompareFolderOrder = nil
    }

    private func scheduleContentMatchingForSelectedFolders() {
        guard !isLoading else { return }

        let folderOrder = compareFolderOrder
        guard folderOrder.count > 1 else {
            if contentMatchingSignature != nil || !contentMatchedAssetIDByKey.isEmpty || isMatchingImageContent {
                contentMatchingTask?.cancel()
                contentMatchingTask = nil
                contentMatchingSignature = nil
                contentMatchedAssetIDByKey = [:]
                isMatchingImageContent = false
            }
            return
        }

        let sourceAssets = visibleSnapshot.scopedAssets.filter { asset in
            folderOrder.contains { assetMatchesFolder(asset, folderPath: $0) }
        }
        let orderedSignatures = folderOrder.flatMap { folderPath in
            sourceAssets.filter { assetMatchesFolder($0, folderPath: folderPath) }.map { asset in
                ContentMatchingAssetSignature(
                    assetID: asset.id,
                    fileSizeBytes: asset.fileSizeBytes,
                    modificationMilliseconds: Int64(
                        (asset.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0) * 1_000
                    )
                )
            }
        }
        let signature = ContentMatchingSignature(folderOrder: folderOrder, assets: orderedSignatures)
        guard signature != contentMatchingSignature else { return }

        let previousSignatures = Dictionary((contentMatchingSignature?.assets ?? []).map { ($0.assetID, $0) }, uniquingKeysWith: { _, latest in latest })
        let unchangedIDs = Set(orderedSignatures.filter { previousSignatures[$0.assetID] == $0 }.map(\.assetID))
        let sameFolders = contentMatchingSignature?.folderOrder == folderOrder
        contentMatchingTask?.cancel()
        contentMatchingTask = nil
        contentMatchingSignature = signature
        contentMatchingGeneration = UUID()
        contentMatchedAssetIDByKey = sameFolders ? contentMatchedAssetIDByKey.filter {
            unchangedIDs.contains($0.key.referenceAssetID) && unchangedIDs.contains($0.value)
        } : [:]

        let plans = contentMatchingPlans(folderOrder: folderOrder, sourceAssets: sourceAssets)
        guard !plans.isEmpty else {
            isMatchingImageContent = false
            return
        }

        let requestedAssetIDs = Set(plans.flatMap { $0.referenceAssetIDs + $0.targetAssetIDs })
        let requests = sourceAssets.compactMap { asset -> ImageContentFingerprintRequest? in
            guard requestedAssetIDs.contains(asset.id), let fileURL = fileURL(for: asset) else { return nil }
            return ImageContentFingerprintRequest(
                assetID: asset.id,
                fileURL: fileURL,
                fileSizeBytes: asset.fileSizeBytes,
                contentModificationDate: asset.contentModificationDate
            )
        }
        guard !requests.isEmpty else {
            isMatchingImageContent = false
            return
        }

        isMatchingImageContent = true
        let generation = contentMatchingGeneration
        let fingerprintService = imageContentFingerprintService
        contentMatchingTask = Task { [weak self] in
            let fingerprints = await fingerprintService.fingerprints(for: requests)
            guard !Task.isCancelled else { return }

            let matches = await Task.detached(priority: .utility) {
                var result: [ContentMatchKey: UUID] = [:]
                var consumedAsTarget: Set<UUID> = []
                for plan in plans {
                    let columnMatches = ImageContentMatcher.bestMatches(
                        referenceAssetIDs: plan.referenceAssetIDs.filter { !consumedAsTarget.contains($0) },
                        targetAssetIDs: plan.targetAssetIDs,
                        fingerprints: fingerprints
                    )
                    for (referenceID, targetID) in columnMatches {
                        consumedAsTarget.insert(targetID)
                        result[
                            ContentMatchKey(
                                referenceAssetID: referenceID,
                                targetFolderPath: plan.targetFolderPath
                            )
                        ] = targetID
                    }
                }
                return result
            }.value
            guard !Task.isCancelled,
                  let self,
                  self.contentMatchingGeneration == generation else {
                return
            }

            self.contentMatchedAssetIDByKey = matches
            self.isMatchingImageContent = false
            self.contentMatchingTask = nil
            self.fillMatchedCompareSlots()
        }
    }

    private func fillMatchedCompareSlots() {
        guard mode == .compare, !compareSession.folderPaths.isEmpty,
              compareSession.folderPaths == compareFolderOrder else { return }
        let current = Set(compareSelectionIDs)
        guard let row = scopedComparison.rows
            .first(where: { slots in current.isSubset(of: Set(slots.compactMap { $0?.id })) }) else { return }
        let ids = row.compactMap { $0?.id }
        guard !current.isEmpty, ids != compareSelectionIDs else { return }
        compareSession.selectionIDs = ids
        selection.setOrdered(ids)
        scheduleMetadataLoad(for: ids)
    }

    private func markCompareGroupsViewed(for assetIDs: [UUID]) {
        let newViewedKeys = Set(assetIDs.compactMap(assetByID).map(\.compareAlignmentKey))
        guard !newViewedKeys.isEmpty else { return }

        let originalCount = viewedCompareGroupKeys.count
        viewedCompareGroupKeys.formUnion(newViewedKeys)
        if viewedCompareGroupKeys.count != originalCount {
            if showUnreviewedOnly {
                rebuildVisibleSnapshot()
                normalizeCompareSessionForVisibleGroups()
            } else {
                objectWillChange.send()
            }
        }
    }

    private func markCompareGroupsViewedForCompletedRatings(_ assetIDs: [UUID]) {
        guard showUnreviewedOnly else { return }

        let groupedIDs = Dictionary(grouping: assetIDs.compactMap(assetByID), by: \.compareAlignmentKey)
            .values
            .filter { group in
                group.count >= 2 && group.allSatisfy { $0.ratingState != .pending }
            }
            .flatMap { $0.map(\.id) }

        markCompareGroupsViewed(for: groupedIDs)
    }

    private func rebuildVisibleSnapshotAndNormalizeSelection() {
        rebuildVisibleSnapshot()
        normalizeSelectionForVisibleAssets()
    }

    private func normalizeCompareSessionForVisibleGroups() {
        normalizeCompareSessionForVisibleGroups(
            preferredSelectionKeys: [],
            preferredFocusedKey: nil,
            preferredOverlayKey: nil,
            preferredTemporaryOverlaySlot: nil,
            previousModeWasCompare: mode == .compare
        )
    }

    private func normalizeCompareSessionForVisibleGroups(
        preferredSelectionKeys: [AssetSelectionKey],
        preferredFocusedKey: AssetSelectionKey?,
        preferredOverlayKey: AssetSelectionKey?,
        preferredTemporaryOverlaySlot: Int?,
        preferredFolderPaths: [String]? = nil,
        previousModeWasCompare: Bool
    ) {
        let visibleIDsByKey = Dictionary(uniqueKeysWithValues: filteredAssets.compactMap { asset in
            assetSelectionKey(for: asset).map { ($0, asset.id) }
        })
        let allIDsByKey = Dictionary(uniqueKeysWithValues: assets.compactMap { asset in
            assetSelectionKey(for: asset).map { ($0, asset.id) }
        })

        let restoredSelectionIDs = restoredCompareSelectionIDs(
            preferredSelectionKeys: preferredSelectionKeys,
            visibleIDsByKey: visibleIDsByKey,
            allIDsByKey: allIDsByKey,
            previousModeWasCompare: previousModeWasCompare
        )
        let shouldRestoreCompare = previousModeWasCompare || mode == .compare

        if shouldRestoreCompare, !restoredSelectionIDs.isEmpty {
            compareSession = CompareSessionState(
                selectionIDs: restoredSelectionIDs,
                folderPaths: preferredFolderPaths ?? compareSession.folderPaths,
                temporaryOverlaySlot: preferredTemporaryOverlaySlot,
                focusedAssetID: preferredFocusedKey.flatMap { visibleIDsByKey[$0] ?? allIDsByKey[$0] },
                overlayAssetID: preferredOverlayKey.flatMap { visibleIDsByKey[$0] ?? allIDsByKey[$0] }
            )
            compareCoordinator.normalize(&compareSession)
            mode = .compare
            selection.focusedAssetID = compareCoordinator.focusedAssetID(in: compareSession) ?? restoredSelectionIDs.first
            selection.setOrdered(restoredSelectionIDs)
            scheduleMetadataLoad(for: restoredSelectionIDs)
            return
        }

        guard showUnreviewedOnly, mode == .compare else {
            if mode == .compare, compareSelectionIDs.isEmpty {
                compareSession = CompareSessionState()
                mode = .grid
            }
            return
        }

        let visibleIDs = visibleSnapshot.assetIDSet
        let currentSelection = compareSelectionIDs
        if !currentSelection.isEmpty, currentSelection.allSatisfy(visibleIDs.contains) {
            return
        }

        guard let nextGroup = viewerCompareGroups.first else {
            compareSession = CompareSessionState()
            mode = .grid
            normalizeSelectionForVisibleAssets()
            return
        }

        enterCompareMode(forAssetIDs: nextGroup.map(\.id), focusedAssetID: nil, markAsViewed: false, preserveFolderSlots: true)
    }

    private func restoredCompareSelectionIDs(
        preferredSelectionKeys: [AssetSelectionKey],
        visibleIDsByKey: [AssetSelectionKey: UUID],
        allIDsByKey: [AssetSelectionKey: UUID],
        previousModeWasCompare: Bool
    ) -> [UUID] {
        let visibleRestoredIDs = visibleSnapshot.idsSortedByVisibleOrder(
            preferredSelectionKeys.compactMap { visibleIDsByKey[$0] }
        )
        guard previousModeWasCompare,
              visibleRestoredIDs.count < 2 else {
            return visibleRestoredIDs
        }

        return idsSortedByAssetOrder(preferredSelectionKeys.compactMap { allIDsByKey[$0] })
    }

    private func applyWorkspaceSnapshot(
        _ snapshot: WorkspaceSnapshot,
        resetPresentation: Bool,
        restoring decisionsToRestore: [String: PersistedAssetDecision]? = nil
    ) {
        if resetPresentation {
            resetWorkspacePresentation()
        }

        libraries = snapshot.libraries.sorted { $0.columnIndex < $1.columnIndex }
        assets = AssetFilenameSortKey.sorted(restoreSessionDecisions(
            decisionsToRestore ?? decisionsForRestoringWorkspace(),
            to: snapshot.assets,
            libraries: libraries
        ))
        compareGroups = snapshot.compareGroups
        keepFolderPath = snapshot.keepFolderPath
        rejectFolderPath = snapshot.rejectFolderPath
        rebuildDerivedCaches()
        normalizeSelectionForVisibleAssets()
    }

    private func applyWorkspaceSnapshot(
        _ snapshot: WorkspaceSnapshot,
        presentation: WorkspacePresentationState?,
        resetPresentation: Bool
    ) {
        let sessionDecisions = decisionsForRestoringWorkspace()
        let previousModeWasCompare = mode == .compare
        let mergeResult = mergePreservingWorkspaceIdentity(snapshot)

        libraries = mergeResult.libraries
        assets = AssetFilenameSortKey.sorted(restoreSessionDecisions(
            sessionDecisions,
            to: mergeResult.assets,
            libraries: libraries
        ))
        compareGroups = CompareGroupingService.buildGroups(libraries: libraries, assets: assets)
        keepFolderPath = snapshot.keepFolderPath
        rejectFolderPath = snapshot.rejectFolderPath
        rebuildDerivedCaches()
        removeStaleImageRefreshTokens()
        invalidateImages(for: mergeResult.changedAssetIDs)

        if resetPresentation {
            resetWorkspacePresentation()
            normalizeSelectionForVisibleAssets()
            return
        }

        restorePresentationState(presentation, previousModeWasCompare: previousModeWasCompare)
    }

    private func applyFailedPreservingReload(_ presentation: WorkspacePresentationState?) {
        // A transient disk or network error must not replace the currently usable
        // workspace with an empty one. Nothing has been mutated before this point.
    }

    private func mergePreservingWorkspaceIdentity(_ snapshot: WorkspaceSnapshot) -> PreservingWorkspaceMergeResult {
        let previousLibrariesByPath = Dictionary(uniqueKeysWithValues: libraries.map { ($0.path, $0) })
        let scannedLibraryPathByID = Dictionary(uniqueKeysWithValues: snapshot.libraries.map { ($0.id, $0.path) })

        let mergedLibraries = snapshot.libraries
            .map { scannedLibrary in
                guard let previousLibrary = previousLibrariesByPath[scannedLibrary.path] else {
                    return scannedLibrary
                }
                return LibraryFolder(
                    id: previousLibrary.id,
                    displayName: scannedLibrary.displayName,
                    path: scannedLibrary.path,
                    columnIndex: scannedLibrary.columnIndex
                )
            }
            .sorted { $0.columnIndex < $1.columnIndex }
        let mergedLibraryIDByPath = Dictionary(uniqueKeysWithValues: mergedLibraries.map { ($0.path, $0.id) })

        let previousAssetByKey = Dictionary(uniqueKeysWithValues: assets.compactMap { asset -> (AssetSelectionKey, AssetRecord)? in
            guard let key = assetSelectionKey(for: asset) else { return nil }
            return (key, asset)
        })

        var changedAssetIDs: Set<UUID> = []
        let mergedAssets = snapshot.assets.compactMap { scannedAsset -> AssetRecord? in
            guard let libraryPath = scannedLibraryPathByID[scannedAsset.libraryID],
                  let mergedLibraryID = mergedLibraryIDByPath[libraryPath] else {
                return nil
            }

            let key = AssetSelectionKey(libraryPath: libraryPath, relativePath: scannedAsset.relativePath)
            guard let previousAsset = previousAssetByKey[key] else {
                var newAsset = scannedAsset
                newAsset.libraryID = mergedLibraryID
                return newAsset
            }

            let fileContentIsUnchanged = previousAsset.fileSizeBytes == scannedAsset.fileSizeBytes
                && previousAsset.contentModificationDate == scannedAsset.contentModificationDate
            if !fileContentIsUnchanged {
                changedAssetIDs.insert(previousAsset.id)
            }

            return AssetRecord(
                id: previousAsset.id,
                libraryID: mergedLibraryID,
                filename: scannedAsset.filename,
                relativePath: scannedAsset.relativePath,
                format: scannedAsset.format,
                fileSizeBytes: scannedAsset.fileSizeBytes,
                width: fileContentIsUnchanged ? previousAsset.width : scannedAsset.width,
                height: fileContentIsUnchanged ? previousAsset.height : scannedAsset.height,
                ratingState: scannedAsset.ratingState,
                appTags: scannedAsset.appTags,
                finderTags: scannedAsset.finderTags,
                isRaw: scannedAsset.isRaw,
                rotationDegrees: scannedAsset.rotationDegrees,
                addedToDirectoryDate: scannedAsset.addedToDirectoryDate,
                contentModificationDate: scannedAsset.contentModificationDate
            )
        }

        return PreservingWorkspaceMergeResult(
            libraries: mergedLibraries,
            assets: mergedAssets,
            changedAssetIDs: changedAssetIDs
        )
    }

    private func removeStaleImageRefreshTokens() {
        let existingAssetIDs = Set(assets.map(\.id))
        let retainedTokens = assetImageRefreshTokens.filter { existingAssetIDs.contains($0.key) }
        if retainedTokens.count != assetImageRefreshTokens.count {
            assetImageRefreshTokens = retainedTokens
        }
    }

    private func capturePresentationState() -> WorkspacePresentationState {
        WorkspacePresentationState(
            selectedLibraryPath: selectedLibraryID.flatMap { libraryPathByID[$0] },
            selectedFolderPath: selectedFolderPath,
            selectedFolderPaths: selectedFolderPaths,
            selectedFolderOrder: selectedFolderOrder,
            selectedAssetRelativePaths: selection.orderedAssetIDs(by: assetOrder).compactMap(assetSelectionKey(for:)),
            focusedAssetRelativePath: selection.focusedAssetID.flatMap(assetSelectionKey(for:)),
            compareSessionRelativePaths: compareSession.selectionIDs.compactMap(assetSelectionKey(for:)),
            compareFolderPaths: compareSession.folderPaths,
            compareFocusedRelativePath: compareSession.focusedAssetID.flatMap(assetSelectionKey(for:)),
            compareOverlayRelativePath: compareCoordinator.overlayAssetID(in: compareSession).flatMap(assetSelectionKey(for:)),
            compareTemporaryOverlaySlot: compareSession.temporaryOverlaySlot,
            mode: mode,
            searchText: searchText,
            showUnreviewedOnly: showUnreviewedOnly,
            viewedCompareGroupKeys: viewedCompareGroupKeys,
            categoryFilter: categoryFilter,
            assetSortMode: assetSortMode
        )
    }

    private func restorePresentationState(
        _ presentation: WorkspacePresentationState?,
        previousModeWasCompare: Bool
    ) {
        guard let presentation else {
            clearSelection()
            compareSession = CompareSessionState()
            if mode == .compare {
                mode = .grid
            }
            return
        }

        let librariesByPath = Dictionary(uniqueKeysWithValues: libraries.map { ($0.path, $0.id) })
        selectedLibraryID = presentation.selectedLibraryPath.flatMap { librariesByPath[$0] }
        selectedFolderOrder = presentation.selectedFolderOrder.filter { path in
            assets.contains { assetMatchesFolder($0, folderPath: path) }
        }
        let availableFolderPaths = Set(selectedFolderOrder)
        let remainingSelectedFolders = presentation.selectedFolderPaths.filter { path in
            availableFolderPaths.contains(path) || assets.contains { assetMatchesFolder($0, folderPath: path) }
        }
        selectedFolderPaths = remainingSelectedFolders
        if let selectedFolderPath = presentation.selectedFolderPath,
           remainingSelectedFolders.contains(selectedFolderPath) || selectedFolderOrder.contains(selectedFolderPath) {
            self.selectedFolderPath = selectedFolderPath
        } else {
            self.selectedFolderPath = selectedFolderOrder.count == 1 ? selectedFolderOrder.first : nil
        }
        searchText = presentation.searchText
        showUnreviewedOnly = presentation.showUnreviewedOnly
        categoryFilter = presentation.categoryFilter
        assetSortMode = presentation.assetSortMode
        viewedCompareGroupKeys = viewedCompareGroupKeys.union(presentation.viewedCompareGroupKeys)
        rebuildVisibleSnapshot()
        normalizeSelectionForVisibleAssets(
            preferredKeys: presentation.selectedAssetRelativePaths,
            focusedKey: presentation.focusedAssetRelativePath
        )
        normalizeCompareSessionForVisibleGroups(
            preferredSelectionKeys: presentation.compareSessionRelativePaths,
            preferredFocusedKey: presentation.compareFocusedRelativePath,
            preferredOverlayKey: presentation.compareOverlayRelativePath,
            preferredTemporaryOverlaySlot: presentation.compareTemporaryOverlaySlot,
            preferredFolderPaths: presentation.compareFolderPaths,
            previousModeWasCompare: previousModeWasCompare || presentation.mode == .compare
        )
    }

    private func assetSelectionKey(for assetID: UUID) -> AssetSelectionKey? {
        guard let asset = assetByID(assetID) else { return nil }
        return assetSelectionKey(for: asset)
    }

    private func assetSelectionKey(for asset: AssetRecord) -> AssetSelectionKey? {
        guard let libraryPath = libraryPathByID[asset.libraryID] else { return nil }
        return AssetSelectionKey(libraryPath: libraryPath, relativePath: asset.relativePath)
    }

    private func resetWorkspacePresentation() {
        selectedLibraryID = nil
        selectedFolderPath = nil
        selectedFolderPaths = []
        selectedFolderOrder = []
        categoryFilter = .all
        assetSortMode = .filename
        selection.clear()
        compareSession = CompareSessionState()
        mode = .grid
    }

    private func emptyWorkspaceSnapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            libraries: [],
            assets: [],
            compareGroups: [],
            keepFolderPath: keepFolderPath,
            rejectFolderPath: rejectFolderPath
        )
    }

    private func makeCurrentDecisionSnapshot() -> [String: PersistedAssetDecision] {
        let libraryPathByID = Dictionary(uniqueKeysWithValues: libraries.map { ($0.id, $0.path) })
        return assets.reduce(into: [String: PersistedAssetDecision]()) { result, asset in
            guard let libraryPath = libraryPathByID[asset.libraryID], let decision = Self.persistedDecision(for: asset) else {
                return
            }
            result[AssetDecisionKey.make(libraryPath: libraryPath, asset: asset)] = decision
        }
    }

    private static func persistedDecision(for asset: AssetRecord) -> PersistedAssetDecision? {
        guard asset.ratingState != .pending || !asset.appTags.isEmpty || asset.normalizedRotationDegrees != 0 else { return nil }
        return PersistedAssetDecision(ratingState: asset.ratingState, appTags: asset.appTags, finderTags: [], rotationDegrees: asset.rotationDegrees)
    }

    private func decisionsForRestoringWorkspace() -> [String: PersistedAssetDecision] {
        savedDecisionSnapshot.merging(makeCurrentDecisionSnapshot()) { _, current in current }
    }

    private func restoreSessionDecisions(
        _ decisions: [String: PersistedAssetDecision],
        to scannedAssets: [AssetRecord],
        libraries: [LibraryFolder]
    ) -> [AssetRecord] {
        let libraryPathByID = Dictionary(uniqueKeysWithValues: libraries.map { ($0.id, $0.path) })
        return scannedAssets.map { asset in
            guard let libraryPath = libraryPathByID[asset.libraryID] else { return asset }
            var restored = asset
            if let persisted = decisions[AssetDecisionKey.make(libraryPath: libraryPath, asset: asset)] {
                restored.ratingState = persisted.ratingState
                restored.appTags = persisted.appTags
                restored.rotationDegrees = AssetRecord.normalizedRotationDegrees(persisted.rotationDegrees)
            }
            // Finder tagging is retired in the UI. Preserve any older pending
            // records, but avoid path/URL normalization for every imported image
            // when there are no legacy edits to restore.
            if !pendingFinderTagEdits.isEmpty {
                let url = URL(fileURLWithPath: libraryPath).appendingPathComponent(asset.relativePath)
                if let pending = pendingFinderTagEdits[PendingFinderTagKey.make(for: url)] {
                    restored.finderTags = pending.tags
                    restored.finderTagSyncIssue = pending.reason
                }
            }
            return restored
        }
    }

    private func makeFolderTree(for libraryAssets: [AssetRecord], libraryID: UUID) -> [FolderTreeNode] {
        var childrenByParent: [String?: [String]] = [:]
        var assetCountByFolder: [String: Int] = [:]
        var knownFolders: Set<String> = []

        for asset in libraryAssets {
            let folderPath = NSString(string: asset.relativePath).deletingLastPathComponent
            guard folderPath != "." else { continue }

            let pathComponents = folderPath.split(separator: "/").map(String.init)
            var currentPath = ""
            var parentPath: String?

            for component in pathComponents {
                currentPath = currentPath.isEmpty ? component : "\(currentPath)/\(component)"
                if knownFolders.insert(currentPath).inserted {
                    childrenByParent[parentPath, default: []].append(currentPath)
                }
                assetCountByFolder[currentPath, default: 0] += 1
                parentPath = currentPath
            }
        }

        func buildNodes(parentPath: String?) -> [FolderTreeNode] {
            let children = (childrenByParent[parentPath] ?? [])
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

            return children.map { path in
                FolderTreeNode(
                    libraryID: libraryID,
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    relativePath: path,
                    assetCount: assetCountByFolder[path, default: 0],
                    children: buildNodes(parentPath: path)
                )
            }
        }

        return buildNodes(parentPath: nil)
    }

    private func scheduleMetadataLoad(for assetIDs: [UUID]) {
        let pendingAssets = assetIDs
            .compactMap { assetIndexByID[$0] }
            .filter { ($0.width <= 0 || $0.height <= 0) && !metadataLoadingAssetIDs.contains($0.id) }

        guard !pendingAssets.isEmpty else { return }

        let pendingIDs = Set(pendingAssets.map(\.id))
        metadataLoadingAssetIDs.formUnion(pendingIDs)

        let libraries = libraries
        let indexingService = indexingService

        Task { [weak self] in
            let metadataByAssetID = (try? await indexingService.loadMetadata(for: pendingAssets, libraries: libraries)) ?? [:]
            await MainActor.run {
                self?.applyMetadata(metadataByAssetID, requestedAssetIDs: pendingIDs)
            }
        }
    }

    private func applyMetadata(_ metadataByAssetID: [UUID: AssetMetadata], requestedAssetIDs: Set<UUID>) {
        defer { metadataLoadingAssetIDs.subtract(requestedAssetIDs) }
        guard !metadataByAssetID.isEmpty else { return }

        var nextAssets = assets
        var didChange = false

        for (assetID, metadata) in metadataByAssetID {
            guard let index = assetArrayIndexByID[assetID] else { continue }
            guard nextAssets[index].width != metadata.width || nextAssets[index].height != metadata.height else {
                continue
            }

            nextAssets[index].width = metadata.width
            nextAssets[index].height = metadata.height
            didChange = true
        }

        guard didChange else { return }
        assets = nextAssets
        // Width/height do not affect membership, sort order, filenames, or
        // content signatures. Refresh record payloads without rebuilding trees,
        // sorting the workspace, or running the matching planner again.
        var updates: [UUID: AssetRecord] = [:]
        for id in metadataByAssetID.keys {
            guard let index = assetArrayIndexByID[id] else { continue }
            updates[id] = nextAssets[index]
            assetIndexByID[id] = nextAssets[index]
        }
        refreshComparisonPayloads(updates)
        var updatedVisible = visibleSnapshot
        updatedVisible.refreshRecordPayloads(updates)
        visibleSnapshot = updatedVisible
    }
}
