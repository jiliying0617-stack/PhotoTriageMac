import Foundation
import PhotoTriageCore
import Testing

@MainActor
struct AppStateCategoryFilterTests {
    @Test
    func categoryFilterShowsRatingBucketsAndCanReturnToAll() async throws {
        let snapshot = makeCategorySnapshot()
        let state = AppState(indexingService: CategoryFilterIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.applyRating(.keep, to: [snapshot.assets[0].id])
        state.applyRating(.reject, to: [snapshot.assets[1].id])

        #expect(state.categorySummary.totalCount == 4)
        #expect(state.categorySummary.keepCount == 1)
        #expect(state.categorySummary.rejectCount == 1)
        #expect(state.categorySummary.pendingCount == 2)
        #expect(state.passRate == Double(3) / Double(4))

        state.selectCategoryFilter(.rating(.keep))
        #expect(state.filteredAssets.map(\.filename) == ["keep.jpg"])

        state.selectCategoryFilter(.rating(.pending))
        #expect(state.filteredAssets.map(\.filename) == ["p0.jpg", "pending.jpg"])

        state.selectCategoryFilter(.rating(.reject))
        #expect(state.filteredAssets.map(\.filename) == ["reject.jpg"])
        #expect(state.passRate == Double(3) / Double(4))

        state.selectCategoryFilter(.all)
        #expect(state.filteredAssets.map(\.filename).sorted() == ["keep.jpg", "p0.jpg", "pending.jpg", "reject.jpg"])
    }

    @Test
    func priorityCategoryFilterUsesCurrentScopeAndAutoRejectsTaggedAssets() async throws {
        let snapshot = makeCategorySnapshot()
        let state = AppState(indexingService: CategoryFilterIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.applyPriorityTag(.p0, to: [snapshot.assets[2].id])
        state.applyPriorityTag(.p1, to: [snapshot.assets[1].id])

        let library = try #require(state.libraries.first)
        state.selectFolder(in: library.id, relativePath: "set-a")

        #expect(state.categorySummary.totalCount == 3)
        #expect(state.categorySummary.priorityTagSummary.p0Count == 1)
        #expect(state.categorySummary.priorityTagSummary.p1Count == 1)
        #expect(state.passRate == Double(1) / Double(3))

        state.selectCategoryFilter(.priority(.p0))
        #expect(state.filteredAssets.map(\.filename) == ["p0.jpg"])
        #expect(state.filteredAssets.first?.ratingState == .reject)
        #expect(state.categorySummary.totalCount == 3)

        state.selectCategoryFilter(.rating(.reject))
        #expect(state.filteredAssets.map(\.filename).sorted() == ["p0.jpg", "reject.jpg"])
        #expect(state.passRate == Double(1) / Double(3))
    }

    @Test
    func pendingNavigationTargetCanBeCapturedBeforeCurrentAssetLeavesFilter() async throws {
        let snapshot = makeCategorySnapshot()
        let state = AppState(indexingService: CategoryFilterIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.selectCategoryFilter(.rating(.pending))
        let visibleIDs = state.filteredAssets.map(\.id)
        let currentID = try #require(visibleIDs.first)
        let expectedNextID = try #require(visibleIDs.dropFirst().first)

        let capturedNextID = state.visibleAssetID(after: currentID)
        state.applyRating(.keep, to: [currentID])

        #expect(capturedNextID == expectedNextID)
        #expect(state.filteredAssets.first?.id == expectedNextID)
    }
}

private func makeCategorySnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "Originals", path: "/imports/originals", columnIndex: 0)
    let assets = [
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "keep.jpg",
            relativePath: "set-a/keep.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "reject.jpg",
            relativePath: "set-a/reject.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "p0.jpg",
            relativePath: "set-a/p0.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "pending.jpg",
            relativePath: "set-b/pending.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/exports/Keep",
        rejectFolderPath: "/exports/Reject"
    )
}

private struct CategoryFilterIndexingService: IndexingService {
    let snapshot: WorkspaceSnapshot

    func loadWorkspace() async throws -> WorkspaceSnapshot {
        snapshot
    }
}
