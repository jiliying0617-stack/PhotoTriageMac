import Foundation
import PhotoTriageCore
import Testing

@MainActor
struct AppStateExportFolderRevealTests {
    @Test
    func revealExportFoldersOpensBothKeepAndRejectDestinationsThatWereExported() async throws {
        let snapshot = makeExportFolderSnapshot()
        let inspectionService = RecordingExportFolderInspectionService()
        let state = AppState(
            indexingService: StaticExportFolderIndexingService(snapshot: snapshot),
            inspectionService: inspectionService
        )

        await state.reloadWorkspace()
        state.revealExportFolders(
            for: ExportExecutionSummary(exportedCount: 3, keepCount: 2, rejectCount: 1, pendingCount: 0)
        )

        #expect(inspectionService.revealedURLs == [
            URL(fileURLWithPath: "/exports/Keep"),
            URL(fileURLWithPath: "/exports/Reject")
        ])
    }

    @Test
    func revealExportFoldersOnlyOpensDestinationsThatActuallyReceivedExports() async throws {
        let snapshot = makeExportFolderSnapshot()
        let inspectionService = RecordingExportFolderInspectionService()
        let state = AppState(
            indexingService: StaticExportFolderIndexingService(snapshot: snapshot),
            inspectionService: inspectionService
        )

        await state.reloadWorkspace()
        state.revealExportFolders(
            for: ExportExecutionSummary(exportedCount: 2, keepCount: 2, rejectCount: 0, pendingCount: 0)
        )

        #expect(inspectionService.revealedURLs == [
            URL(fileURLWithPath: "/exports/Keep")
        ])
    }

    @Test
    func revealExportFoldersNoOpsWhenSummaryContainsNoExportedDestination() async throws {
        let snapshot = makeExportFolderSnapshot()
        let inspectionService = RecordingExportFolderInspectionService()
        let state = AppState(
            indexingService: StaticExportFolderIndexingService(snapshot: snapshot),
            inspectionService: inspectionService
        )

        await state.reloadWorkspace()
        state.revealExportFolders(
            for: ExportExecutionSummary(exportedCount: 0, keepCount: 0, rejectCount: 0, pendingCount: 0)
        )

        #expect(inspectionService.revealedURLs.isEmpty)
    }

    @Test
    func revealKeepExportFolderOpensKeepDestinationOnly() async throws {
        let snapshot = makeExportFolderSnapshot()
        let inspectionService = RecordingExportFolderInspectionService()
        let state = AppState(
            indexingService: StaticExportFolderIndexingService(snapshot: snapshot),
            inspectionService: inspectionService
        )

        await state.reloadWorkspace()
        state.revealKeepExportFolder()

        #expect(inspectionService.revealedURLs == [
            URL(fileURLWithPath: "/exports/Keep")
        ])
    }

    @Test
    func revealRejectExportFolderOpensRejectDestinationOnly() async throws {
        let snapshot = makeExportFolderSnapshot()
        let inspectionService = RecordingExportFolderInspectionService()
        let state = AppState(
            indexingService: StaticExportFolderIndexingService(snapshot: snapshot),
            inspectionService: inspectionService
        )

        await state.reloadWorkspace()
        state.revealRejectExportFolder()

        #expect(inspectionService.revealedURLs == [
            URL(fileURLWithPath: "/exports/Reject")
        ])
    }
}

private func makeExportFolderSnapshot() -> WorkspaceSnapshot {
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

private struct StaticExportFolderIndexingService: IndexingService {
    let snapshot: WorkspaceSnapshot

    func loadWorkspace() async throws -> WorkspaceSnapshot {
        snapshot
    }
}

private final class RecordingExportFolderInspectionService: AssetInspectionService, @unchecked Sendable {
    private(set) var revealedURLs: [URL] = []

    func revealInFinder(_ url: URL) {
        revealedURLs.append(url)
    }

    func quickLook(_ url: URL) {}
}
