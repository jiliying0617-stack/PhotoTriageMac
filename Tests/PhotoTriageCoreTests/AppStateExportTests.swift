import Foundation
import PhotoTriageCore
import Testing

@MainActor
struct AppStateExportTests {
    @Test
    func exportUsesOnlySelectedFoldersIncludingChildrenButNotSimilarPrefixesOrOtherLibraries() async throws {
        let snapshot = makeExportScopeSnapshot()
        let executor = RecordingExportExecutor()
        let state = AppState(indexingService: StaticExportIndexingService(snapshot: snapshot), exportExecutor: executor)
        await state.reloadWorkspace()
        let library = snapshot.libraries[0]
        state.toggleFolderSelection(in: library.id, relativePath: "set-b")
        state.toggleFolderSelection(in: library.id, relativePath: "set-a")

        _ = try await state.exportDecisions(includePending: true)

        let request = try #require(executor.recordedRequests.first)
        #expect(Set(request.assets.map(\.relativePath)) == ["set-a/keep.jpg", "set-a/nested/pending.jpg", "set-b/reject.jpg"])
        #expect(request.assets.allSatisfy { $0.libraryID == library.id })
        #expect(state.exportScopeDescription == "当前库 / set-b、set-a")
        #expect(state.exportScopeSummary.totalCount == 3)
        #expect(state.exportScopeSummary.keepCount == 1)
        #expect(state.exportScopeSummary.rejectCount == 1)
        #expect(state.exportScopeSummary.pendingCount == 1)
    }

    @Test
    func exportScopeAndTagCountsIgnoreBrowsingFiltersAndExcludeUnselectedFolders() async throws {
        var snapshot = makeExportScopeSnapshot()
        for index in snapshot.assets.indices {
            snapshot.assets[index].finderTags = [FinderTag(name: "蓝色", color: .blue)]
        }
        let executor = RecordingExportExecutor()
        let state = AppState(indexingService: StaticExportIndexingService(snapshot: snapshot), exportExecutor: executor)
        await state.reloadWorkspace()
        state.toggleFolderSelection(in: snapshot.libraries[0].id, relativePath: "set-a")
        state.toggleFolderSelection(in: snapshot.libraries[0].id, relativePath: "set-b")
        state.applyPriorityTag(.p0, to: [snapshot.assets[0].id, snapshot.assets[3].id])
        state.selectCategoryFilter(.rating(.pending))
        state.searchText = "no-such-visible-result"
        state.showUnreviewedOnly = true
        #expect(state.filteredAssets.isEmpty)

        _ = try await state.exportDecisions(
            priorityTagFolderPaths: [.p0: "/exports/P0"],
            finderTagFolderPaths: [.blue: "/exports/Blue"],
            includeKeep: false, includeReject: false,
            includedPriorityTags: [.p0], includedFinderTagColors: [.blue]
        )

        let request = try #require(executor.recordedRequests.first)
        #expect(Set(request.assets.map(\.relativePath)) == ["set-a/keep.jpg", "set-a/nested/pending.jpg", "set-b/reject.jpg"])
        #expect(state.exportScopeSummary.totalCount == 3)
        #expect(state.exportScopeSummary.priorityTagSummary.p0Count == 1)
        #expect(state.exportScopeSummary.finderTagColorSummary.count(for: .blue) == 3)
    }

    @Test
    func exportScopeHandlesEmptyFoldersOverlappingSelectionsLibraryRootAndAllLibraries() async throws {
        let snapshot = makeExportScopeSnapshot()
        let executor = RecordingExportExecutor()
        let state = AppState(indexingService: StaticExportIndexingService(snapshot: snapshot), exportExecutor: executor)
        await state.reloadWorkspace()
        let libraryID = snapshot.libraries[0].id
        state.selectFolder(in: libraryID, relativePath: "set-a")
        state.toggleFolderSelection(in: libraryID, relativePath: "set-a/nested")
        _ = try await state.exportDecisions(includePending: true)
        #expect(executor.recordedRequests.last?.assets.count == 2)
        #expect(state.exportScopeSummary.totalCount == 2)

        state.selectFolder(in: libraryID, relativePath: "empty")
        _ = try await state.exportDecisions(includePending: true)
        #expect(executor.recordedRequests.last?.assets.isEmpty == true)
        #expect(state.exportScopeSummary.totalCount == 0)

        state.selectLibrary(libraryID)
        _ = try await state.exportDecisions(includePending: true)
        #expect(executor.recordedRequests.last?.assets.count == 5)
        #expect(state.exportScopeSummary.totalCount == 5)

        state.selectLibrary(nil)
        _ = try await state.exportDecisions(includePending: true)
        #expect(executor.recordedRequests.last?.assets.count == 6)
        #expect(state.exportScopeSummary.totalCount == 6)
    }

    @Test
    func selectedFolderExportCopiesOnlyScopedFilesToDisk() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("export-scope-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source")
        let output = root.appendingPathComponent("output")
        let snapshot = makeExportScopeSnapshot(rootPath: source.path)
        for asset in snapshot.assets where asset.libraryID == snapshot.libraries[0].id {
            let url = source.appendingPathComponent(asset.relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(asset.relativePath.utf8).write(to: url)
        }
        let state = AppState(indexingService: StaticExportIndexingService(snapshot: snapshot), exportExecutor: FileSystemExportService())
        await state.reloadWorkspace()
        state.toggleFolderSelection(in: snapshot.libraries[0].id, relativePath: "set-a")
        state.toggleFolderSelection(in: snapshot.libraries[0].id, relativePath: "set-b")
        let summary = try await state.exportDecisions(
            keepFolderPath: output.appendingPathComponent("Keep").path,
            rejectFolderPath: output.appendingPathComponent("Reject").path,
            pendingFolderPath: output.appendingPathComponent("Pending").path,
            includePending: true
        )
        #expect(summary.exportedCount == 3)
        for path in ["Keep/set-a/keep.jpg", "Reject/set-b/reject.jpg", "Pending/set-a/nested/pending.jpg"] {
            #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent(path).path))
        }
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("Keep/set-a-copy").path))
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("Reject/set-c").path))
    }

    @Test
    func exportDecisionsPassesCurrentWorkspaceStateToExportExecutor() async throws {
        let snapshot = makeExportSnapshot()
        let executor = RecordingExportExecutor()
        let state = AppState(
            indexingService: StaticExportIndexingService(snapshot: snapshot),
            exportExecutor: executor,
        )

        await state.reloadWorkspace()
        state.applyRating(.keep, to: [snapshot.assets[0].id])
        state.applyRating(.reject, to: [snapshot.assets[1].id])

        let summary = try await state.exportDecisions()

        #expect(summary.exportedCount == 2)
        #expect(executor.recordedRequests.count == 1)
        #expect(executor.recordedRequests[0].keepFolderPath == "/exports/Keep")
        #expect(executor.recordedRequests[0].rejectFolderPath == "/exports/Reject")
        #expect(executor.recordedRequests[0].includePending == false)
        #expect(executor.recordedRequests[0].assets.first(where: { $0.id == snapshot.assets[0].id })?.ratingState == .keep)
        #expect(executor.recordedRequests[0].assets.first(where: { $0.id == snapshot.assets[1].id })?.ratingState == .reject)
    }

    @Test
    func exportDecisionsCanUseCustomFoldersAndFilterBuckets() async throws {
        let snapshot = makeExportSnapshot()
        let executor = RecordingExportExecutor()
        let state = AppState(
            indexingService: StaticExportIndexingService(snapshot: snapshot),
            exportExecutor: executor,
        )

        await state.reloadWorkspace()
        state.applyRating(.keep, to: [snapshot.assets[0].id])
        state.applyRating(.reject, to: [snapshot.assets[1].id])

        _ = try await state.exportDecisions(
            keepFolderPath: "/custom/batch/保留",
            rejectFolderPath: "/custom/batch/淘汰",
            pendingFolderPath: "/custom/batch/未处理",
            includeKeep: true,
            includeReject: false
        )

        #expect(executor.recordedRequests.count == 1)
        #expect(executor.recordedRequests[0].keepFolderPath == "/custom/batch/保留")
        #expect(executor.recordedRequests[0].rejectFolderPath == "/custom/batch/淘汰")
        #expect(executor.recordedRequests[0].assets.map(\.ratingState) == [.keep])
    }

    @Test
    func exportDecisionsRoutesUntaggedAssetsToPendingWhenIncluded() async throws {
        let snapshot = makeExportSnapshot()
        let executor = RecordingExportExecutor()
        let state = AppState(
            indexingService: StaticExportIndexingService(snapshot: snapshot),
            exportExecutor: executor,
        )

        await state.reloadWorkspace()
        state.applyRating(.keep, to: [snapshot.assets[0].id])
        state.applyRating(.reject, to: [snapshot.assets[1].id])

        _ = try await state.exportDecisions(
            keepFolderPath: "/custom/batch/保留",
            rejectFolderPath: "/custom/batch/淘汰",
            pendingFolderPath: "/custom/batch/未处理",
            includeKeep: false,
            includeReject: false,
            includePending: true
        )

        #expect(executor.recordedRequests.count == 1)
        #expect(executor.recordedRequests[0].pendingFolderPath == "/custom/batch/未处理")
        #expect(executor.recordedRequests[0].includePending)
        #expect(executor.recordedRequests[0].assets.map(\.filename) == ["pending.jpg"])
        #expect(executor.recordedRequests[0].assets.map(\.ratingState) == [.pending])
    }

    @Test
    func exportDecisionsDoesNotMutateOriginalClassificationState() async throws {
        let snapshot = makeExportSnapshot()
        let executor = RecordingExportExecutor()
        let state = AppState(
            indexingService: StaticExportIndexingService(snapshot: snapshot),
            exportExecutor: executor
        )

        await state.reloadWorkspace()
        state.applyRating(.keep, to: [snapshot.assets[0].id])
        state.applyRating(.reject, to: [snapshot.assets[1].id])

        _ = try await state.exportDecisions(includePending: true)

        #expect(state.assets.first { $0.filename == "keep.jpg" }?.ratingState == .keep)
        #expect(state.assets.first { $0.filename == "reject.jpg" }?.ratingState == .reject)
        #expect(state.assets.first { $0.filename == "pending.jpg" }?.ratingState == .pending)
        #expect(state.keepCount == 1)
        #expect(state.rejectCount == 1)
        #expect(state.pendingCount == 1)
    }

    @Test
    func priorityTagsAreExclusiveAndIncludedInExportRequests() async throws {
        let snapshot = makeExportSnapshot()
        let executor = RecordingExportExecutor()
        let state = AppState(
            indexingService: StaticExportIndexingService(snapshot: snapshot),
            exportExecutor: executor
        )

        await state.reloadWorkspace()
        state.applyRating(.keep, to: [snapshot.assets[0].id])
        state.applyRating(.reject, to: [snapshot.assets[1].id])
        state.applyPriorityTag(.p0, to: [snapshot.assets[0].id])
        state.applyPriorityTag(.p1, to: [snapshot.assets[1].id])
        state.applyPriorityTag(.p2, to: [snapshot.assets[1].id])

        _ = try await state.exportDecisions(
            priorityTagFolderPaths: [
                .p0: "/custom/batch/P0",
                .p1: "/custom/batch/P1",
                .p2: "/custom/batch/P2",
            ],
            includeKeep: false,
            includeReject: false,
            includedPriorityTags: [.p0, .p2]
        )

        #expect(state.priorityTagSummary.p0Count == 1)
        #expect(state.priorityTagSummary.p1Count == 0)
        #expect(state.priorityTagSummary.p2Count == 1)
        #expect(state.passRate == Double(1) / Double(3))
        #expect(state.assets.first { $0.filename == "keep.jpg" }?.ratingState == .reject)
        #expect(state.assets.first { $0.filename == "reject.jpg" }?.ratingState == .reject)
        #expect(executor.recordedRequests.count == 1)
        #expect(executor.recordedRequests[0].includedPriorityTags == [.p0, .p2])
        #expect(executor.recordedRequests[0].priorityTagFolderPaths[.p0] == "/custom/batch/P0")
        #expect(executor.recordedRequests[0].assets.map(\.filename).sorted() == ["keep.jpg", "reject.jpg"])
        #expect(executor.recordedRequests[0].assets.first { $0.filename == "reject.jpg" }?.priorityTag == .p2)
    }

    @Test
    func priorityTagsCanBeClearedAfterEditing() async throws {
        let snapshot = makeExportSnapshot()
        let state = AppState(
            indexingService: StaticExportIndexingService(snapshot: snapshot)
        )

        await state.reloadWorkspace()
        state.applyPriorityTag(.p0, to: [snapshot.assets[0].id])
        state.applyPriorityTag(.p2, to: [snapshot.assets[0].id])
        state.clearPriorityTags(from: [snapshot.assets[0].id])

        #expect(state.priorityTagSummary.taggedCount == 0)
        #expect(state.assets.first { $0.id == snapshot.assets[0].id }?.priorityTag == nil)
        #expect(state.assets.first { $0.id == snapshot.assets[0].id }?.ratingState == .reject)
    }

    @Test
    func finderColorTaggedAssetsCanBeExportedWithoutRatingBuckets() async throws {
        var snapshot = makeExportSnapshot()
        snapshot.assets[0].finderTags = [FinderTag(name: "精选", color: .red)]
        let executor = RecordingExportExecutor()
        let state = AppState(
            indexingService: StaticExportIndexingService(snapshot: snapshot),
            exportExecutor: executor
        )
        await state.reloadWorkspace()

        _ = try await state.exportDecisions(
            finderTagFolderPaths: [.red: "/custom/batch/Finder标签/红色"],
            includeKeep: false,
            includeReject: false,
            includePending: false,
            includedFinderTagColors: [.red]
        )

        let request = try #require(executor.recordedRequests.first)
        #expect(request.assets.map(\.filename) == ["keep.jpg"])
        #expect(request.includedFinderTagColors == [.red])
        #expect(request.finderTagFolderPaths[.red] == "/custom/batch/Finder标签/红色")
    }

    @Test
    func clearAllTriageTagsRestoresPendingAndRemovesPriorityTags() async throws {
        let snapshot = makeExportSnapshot()
        let state = AppState(
            indexingService: StaticExportIndexingService(snapshot: snapshot)
        )

        await state.reloadWorkspace()
        state.applyPriorityTag(.p0, to: [snapshot.assets[0].id])
        state.clearAllTriageTags(from: [snapshot.assets[0].id])

        let asset = try #require(state.assets.first { $0.id == snapshot.assets[0].id })
        #expect(asset.ratingState == .pending)
        #expect(asset.priorityTag == nil)
        #expect(state.priorityTagSummary.taggedCount == 0)
    }

    @Test
    func clearAllTriageTagsFromWorkspaceClearsEveryAsset() async throws {
        let snapshot = makeExportSnapshot()
        let state = AppState(
            indexingService: StaticExportIndexingService(snapshot: snapshot)
        )

        await state.reloadWorkspace()
        #expect(state.hasAnyTriageTags == false)

        state.applyRating(.keep, to: [snapshot.assets[0].id])
        state.applyRating(.reject, to: [snapshot.assets[1].id])
        state.applyPriorityTag(.p2, to: [snapshot.assets[2].id])

        #expect(state.hasAnyTriageTags == true)

        state.clearAllTriageTagsFromWorkspace()

        #expect(state.assets.allSatisfy { $0.ratingState == .pending })
        #expect(state.assets.allSatisfy { $0.priorityTag == nil })
        #expect(state.priorityTagSummary.taggedCount == 0)
        #expect(state.hasAnyTriageTags == false)
    }
}

private func makeExportScopeSnapshot(rootPath: String = "/imports/export-scope") -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "当前库", path: rootPath, columnIndex: 0)
    let otherLibrary = LibraryFolder(displayName: "其他库", path: "/imports/other-export-scope", columnIndex: 1)
    let paths: [(String, RatingState)] = [
        ("set-a/keep.jpg", .keep), ("set-b/reject.jpg", .reject),
        ("set-a/nested/pending.jpg", .pending), ("set-a-copy/wrong.jpg", .keep),
        ("set-c/wrong.jpg", .reject)
    ]
    var assets = paths.map { path, rating in
        AssetRecord(libraryID: library.id, filename: URL(fileURLWithPath: path).lastPathComponent,
                    relativePath: path, format: .jpg, fileSizeBytes: 100, width: 1, height: 1, ratingState: rating)
    }
    assets.append(AssetRecord(libraryID: otherLibrary.id, filename: "wrong-library.jpg",
                              relativePath: "set-a/wrong-library.jpg", format: .jpg,
                              fileSizeBytes: 100, width: 1, height: 1, ratingState: .keep))
    return WorkspaceSnapshot(libraries: [library, otherLibrary], assets: assets, compareGroups: [],
                             keepFolderPath: "/exports/Keep", rejectFolderPath: "/exports/Reject")
}

private func makeExportSnapshot() -> WorkspaceSnapshot {
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
            height: 1,
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "reject.jpg",
            relativePath: "set-b/reject.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1,
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "pending.jpg",
            relativePath: "set-c/pending.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1,
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

private struct StaticExportIndexingService: IndexingService {
    let snapshot: WorkspaceSnapshot

    func loadWorkspace() async throws -> WorkspaceSnapshot {
        snapshot
    }
}

private final class RecordingExportExecutor: ExportExecuting, @unchecked Sendable {
    private(set) var recordedRequests: [ExportRequest] = []

    func export(_ request: ExportRequest) async throws -> ExportExecutionSummary {
        recordedRequests.append(request)
        return ExportExecutionSummary(exportedCount: 2, keepCount: 1, rejectCount: 1, pendingCount: 0)
    }
}
