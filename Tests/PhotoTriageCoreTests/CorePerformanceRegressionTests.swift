import Foundation
@testable import PhotoTriageCore
import Testing

@MainActor
struct CorePerformanceRegressionTests {
    @Test
    func repeatedDecisionEditsPreserveRowsAndSkipIdenticalWrites() async throws {
        let fixture = makeCorePerformanceFixture(count: 20_000)
        let decisions = CountingDecisionStore()
        let state = AppState(indexingService: CorePerformanceIndexingService(snapshot: fixture), decisionStore: decisions)
        await state.reloadWorkspace()
        for folder in ["A", "B", "C", "D", "E"] {
            state.toggleFolderSelection(in: fixture.libraries[0].id, relativePath: folder)
        }
        let rowIDs = state.visibleCompareRows.map { $0.map { $0?.id } }
        let initialIDs = state.filteredAssets.map(\.id)
        let targets = state.visibleCompareRows[100].compactMap { $0?.id }
        let clock = ContinuousClock()
        let start = clock.now
        for index in 0..<20 {
            state.applyPriorityTag(index.isMultiple(of: 2) ? .p0 : .p1, to: targets)
        }
        print("20k records / 5 folders / 20 group P-tag edits: \(start.duration(to: clock.now))")
        #expect(state.filteredAssets.map(\.id) == initialIDs)
        #expect(state.visibleCompareRows.map { $0.map { $0?.id } } == rowIDs)
        #expect(state.visibleCompareRows[100].compactMap { $0?.priorityTag } == Array(repeating: .p1, count: 5))
        #expect(state.categorySummary.rejectCount == 5)
        #expect(state.categorySummary.priorityTagSummary.p1Count == 5)
        #expect(state.priorityTagSummary.p0Count == 0)
        #expect(decisions.saveCount == 20)
        state.applyPriorityTag(.p1, to: targets)
        state.applyPriorityTag(.p1, to: [UUID()])
        #expect(decisions.saveCount == 20)
        state.clearAllTriageTags(from: targets)
        #expect(state.categorySummary.rejectCount == 0)
        #expect(state.priorityTagSummary.taggedCount == 0)
        #expect(decisions.loadDecisions().isEmpty)
    }

    @Test
    func incrementalDecisionsMatchFullQueryAcrossFiltersAndMetadataChanges() {
        let fixture = makeCorePerformanceFixture(count: 20)
        for filter: AssetCategoryFilter in [.all, .rating(.pending), .rating(.reject), .priority(.p1)] {
            let query = VisibleAssetQuery(selectedFolderPaths: ["A", "C"], selectedFolderOrder: ["C", "A"], categoryFilter: filter)
            var snapshot = VisibleAssetSnapshot(query: query, assets: fixture.assets, includeBasenameCompareGroups: false)
            var edited = fixture.assets
            edited[0].width = 777
            snapshot.refreshRecordPayloads([edited[0].id: edited[0]])
            edited[1].ratingState = .reject
            edited[1].appTags = [PriorityTag.p1.appTag]
            edited[9].ratingState = .keep
            let updated = snapshot.updateDecisionRecords([edited[1].id: edited[1], edited[9].id: edited[9]])
            #expect(updated)
            let rebuilt = VisibleAssetSnapshot(query: query, assets: edited, includeBasenameCompareGroups: false)
            #expect(snapshot == rebuilt)
        }
        var searched = VisibleAssetSnapshot(query: VisibleAssetQuery(searchText: "P1"), assets: fixture.assets)
        let updatedSearch = searched.updateDecisionRecords([fixture.assets[0].id: fixture.assets[0]])
        #expect(!updatedSearch)
    }

    @Test
    func newlyTaggedImagesBecomeVisibleInPreviouslyEmptyPriorityComparison() async {
        let fixture = makeCorePerformanceFixture(count: 20)
        let state = AppState(indexingService: CorePerformanceIndexingService(snapshot: fixture))
        await state.reloadWorkspace()
        for folder in ["A", "B", "C", "D", "E"] {
            state.toggleFolderSelection(in: fixture.libraries[0].id, relativePath: folder)
        }
        let targets = state.visibleCompareRows[1].compactMap { $0?.id }
        state.selectCategoryFilter(.priority(.p1))
        #expect(state.filteredAssets.isEmpty)
        #expect(state.visibleCompareRows.isEmpty)
        state.applyPriorityTag(.p1, to: targets)
        #expect(Set(state.filteredAssets.map(\.id)) == Set(targets))
        #expect(state.visibleCompareRows.count == 1)
        #expect(state.visibleCompareRows.first?.compactMap { $0?.id } == targets)
        state.clearPriorityTags(from: targets)
        #expect(state.visibleCompareRows.isEmpty)
        #expect(state.categorySummary.rejectCount == 5)
    }

    @Test
    func jsonWriterFlushesNewestSnapshotAndDoesNotResurrectClearedDecisions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("decisions.json")
        let store = JSONAssetDecisionStore(fileURL: fileURL)
        var latest: [String: PersistedAssetDecision] = [:]
        for index in 0..<200 {
            latest["asset-\(index)"] = PersistedAssetDecision(ratingState: .reject, appTags: [.init(name: "P1")], finderTags: [])
            store.saveDecisions(latest)
        }
        #expect(store.loadDecisions() == latest)
        store.flushPendingWrites()
        #expect(JSONAssetDecisionStore(fileURL: fileURL).loadDecisions() == latest)
        store.saveDecisions(latest)
        store.clearDecisions()
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(store.loadDecisions().isEmpty)
        let final = ["new": PersistedAssetDecision(ratingState: .keep, appTags: [], finderTags: [])]
        store.saveDecisions(final)
        store.flushPendingWrites()
        #expect(JSONAssetDecisionStore(fileURL: fileURL).loadDecisions() == final)
    }
}

private func makeCorePerformanceFixture(count: Int) -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "Performance", path: "/tmp/state-only-performance", columnIndex: 0)
    let folders = ["A", "B", "C", "D", "E"]
    let perFolder = count / folders.count
    let assets = folders.flatMap { folder in
        (0..<perFolder).map { index in
            let filename = String(format: "image%05d_1.png", index)
            return AssetRecord(libraryID: library.id, filename: filename, relativePath: "\(folder)/\(filename)",
                               format: .png, fileSizeBytes: 1, width: 100, height: 100)
        }
    }
    return WorkspaceSnapshot(libraries: [library], assets: assets, compareGroups: [], keepFolderPath: "", rejectFolderPath: "")
}

private struct CorePerformanceIndexingService: IndexingService {
    let snapshot: WorkspaceSnapshot
    func loadWorkspace() async throws -> WorkspaceSnapshot { snapshot }
}

private final class CountingDecisionStore: AssetDecisionPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var decisions: [String: PersistedAssetDecision] = [:]
    private var writes = 0
    var saveCount: Int { lock.withLock { writes } }
    func loadDecisions() -> [String: PersistedAssetDecision] { lock.withLock { decisions } }
    func saveDecisions(_ next: [String: PersistedAssetDecision]) {
        lock.withLock { decisions = next; writes += 1 }
    }
    func clearDecisions() { lock.withLock { decisions = [:] } }
}
