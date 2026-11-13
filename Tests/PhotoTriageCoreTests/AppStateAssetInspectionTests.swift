import Foundation
import PhotoTriageCore
import Testing

@MainActor
struct AppStateAssetInspectionTests {
    @Test
    func revealSelectedAssetPassesResolvedFileURLToInspectionService() async throws {
        let snapshot = makeInspectionSnapshot()
        let inspectionService = RecordingAssetInspectionService()
        let state = AppState(
            indexingService: StaticInspectionIndexingService(snapshot: snapshot),
            inspectionService: inspectionService
        )

        await state.reloadWorkspace()
        state.select(assetID: snapshot.assets[1].id)

        state.revealSelectedAssetInFinder()

        #expect(inspectionService.revealedURLs == [
            URL(fileURLWithPath: "/imports/originals/set-b/reject.jpg")
        ])
        #expect(inspectionService.quickLookedURLs.isEmpty)
    }

    @Test
    func quickLookSelectedAssetPassesResolvedFileURLToInspectionService() async throws {
        let snapshot = makeInspectionSnapshot()
        let inspectionService = RecordingAssetInspectionService()
        let state = AppState(
            indexingService: StaticInspectionIndexingService(snapshot: snapshot),
            inspectionService: inspectionService
        )

        await state.reloadWorkspace()
        state.select(assetID: snapshot.assets[0].id)

        state.quickLookSelectedAsset()

        #expect(inspectionService.quickLookedURLs == [
            URL(fileURLWithPath: "/imports/originals/set-a/keep.jpg")
        ])
        #expect(inspectionService.revealedURLs.isEmpty)
    }

    @Test
    func inspectionActionsNoOpWhenSelectedAssetLibraryCannotBeResolved() async throws {
        let snapshot = makeInspectionSnapshotWithMissingLibraryReference()
        let inspectionService = RecordingAssetInspectionService()
        let state = AppState(
            indexingService: StaticInspectionIndexingService(snapshot: snapshot),
            inspectionService: inspectionService
        )

        await state.reloadWorkspace()
        state.select(assetID: snapshot.assets[0].id)

        state.revealSelectedAssetInFinder()
        state.quickLookSelectedAsset()

        #expect(inspectionService.revealedURLs.isEmpty)
        #expect(inspectionService.quickLookedURLs.isEmpty)
    }

    @Test
    func fileURLForAssetResolvesAgainstMatchingLibraryPath() async throws {
        let snapshot = makeInspectionSnapshot()
        let state = AppState(indexingService: StaticInspectionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let resolvedURL = state.fileURL(for: snapshot.assets[0])

        #expect(resolvedURL == URL(fileURLWithPath: "/imports/originals/set-a/keep.jpg"))
    }

    @Test
    func fileURLForAssetReturnsNilWhenLibraryCannotBeResolved() async throws {
        let snapshot = makeInspectionSnapshotWithMissingLibraryReference()
        let state = AppState(indexingService: StaticInspectionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let resolvedURL = state.fileURL(for: snapshot.assets[0])

        #expect(resolvedURL == nil)
    }
}

private func makeInspectionSnapshot() -> WorkspaceSnapshot {
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
            relativePath: "set-b/reject.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        )
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/exports/Keep",
        rejectFolderPath: "/exports/Reject"
    )
}

private func makeInspectionSnapshotWithMissingLibraryReference() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "Originals", path: "/imports/originals", columnIndex: 0)
    let orphanLibraryID = UUID()
    let orphanAsset = AssetRecord(
        id: UUID(),
        libraryID: orphanLibraryID,
        filename: "orphan.jpg",
        relativePath: "set-z/orphan.jpg",
        format: .jpg,
        fileSizeBytes: 100,
        width: 1,
        height: 1
    )

    return WorkspaceSnapshot(
        libraries: [library],
        assets: [orphanAsset],
        compareGroups: [],
        keepFolderPath: "/exports/Keep",
        rejectFolderPath: "/exports/Reject"
    )
}

private struct StaticInspectionIndexingService: IndexingService {
    let snapshot: WorkspaceSnapshot

    func loadWorkspace() async throws -> WorkspaceSnapshot {
        snapshot
    }
}

private final class RecordingAssetInspectionService: AssetInspectionService, @unchecked Sendable {
    private(set) var revealedURLs: [URL] = []
    private(set) var quickLookedURLs: [URL] = []

    func revealInFinder(_ url: URL) {
        revealedURLs.append(url)
    }

    func quickLook(_ url: URL) {
        quickLookedURLs.append(url)
    }
}
