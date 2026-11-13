import Foundation
import PhotoTriageCore
import Testing

/// Deliberately uses only APIs available before this performance patch.
/// Run this same file against baseline and revised code, serially, in release:
/// swift test -c release --filter CoreTaggingBenchmarkTests
@MainActor
struct CoreTaggingBenchmarkTests {
    @Test
    func twentyThousandRecordsFiveFoldersTwentyGroupTagSwitches() async {
        let library = LibraryFolder(displayName: "Benchmark", path: "/tmp/state-only-tag-benchmark", columnIndex: 0)
        let folders = ["A", "B", "C", "D", "E"]
        let assets = folders.flatMap { folder in
            (0..<4_000).map { index in
                let name = String(format: "image%05d_1.png", index)
                return AssetRecord(libraryID: library.id, filename: name, relativePath: "\(folder)/\(name)",
                                   format: .png, fileSizeBytes: 1, width: 100, height: 100)
            }
        }
        let snapshot = WorkspaceSnapshot(libraries: [library], assets: assets, compareGroups: [], keepFolderPath: "", rejectFolderPath: "")
        let state = AppState(indexingService: TagBenchmarkIndexingService(snapshot: snapshot))
        let clock = ContinuousClock()
        let setupStart = clock.now
        await state.reloadWorkspace()
        for folder in folders { state.toggleFolderSelection(in: library.id, relativePath: folder) }
        let initialRows = state.visibleCompareRows.map { $0.map { $0?.id } }
        let targets = initialRows[100].compactMap(\.self)
        print("TAG BENCHMARK setup 20k / 5 folders: \(setupStart.duration(to: clock.now))")
        let start = clock.now
        for iteration in 0..<20 {
            state.applyPriorityTag(iteration.isMultiple(of: 2) ? .p0 : .p1, to: targets)
            // Consume the rows each time, just as UI's comparison view does.
            #expect(state.visibleCompareRows.count == 4_000)
        }
        print("TAG BENCHMARK 20k / 5 folders / 20 edits + row reads: \(start.duration(to: clock.now))")
        #expect(state.visibleCompareRows.map { $0.map { $0?.id } } == initialRows)
        #expect(state.categorySummary.rejectCount == 5)
        #expect(state.categorySummary.priorityTagSummary.p1Count == 5)
        #expect(state.filteredAssets.count == 20_000)
    }
}

private struct TagBenchmarkIndexingService: IndexingService {
    let snapshot: WorkspaceSnapshot
    func loadWorkspace() async throws -> WorkspaceSnapshot { snapshot }
}
