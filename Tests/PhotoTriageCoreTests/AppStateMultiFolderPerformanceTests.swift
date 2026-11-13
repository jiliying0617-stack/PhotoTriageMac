import Foundation
import PhotoTriageCore
import Testing

/// Synthetic state-only benchmark: no image decoding, disk enumeration, or network I/O.
/// Run in isolation to compare changes without unrelated concurrent test activity:
/// swift test --filter AppStateMultiFolderPerformanceTests
@MainActor
struct AppStateMultiFolderPerformanceTests {
    @Test
    func sixteenHundredAssetsKeepSparseNumericRowsStableAcrossRepeatedReads() async throws {
        let fixture = makeFiveFolderFixture()
        #expect(fixture.snapshot.assets.count == 1_600)
        let state = AppState(
            indexingService: PerformanceSnapshotIndexingService(snapshot: fixture.snapshot),
            imageContentFingerprintService: PerformanceEmptyFingerprintService()
        )
        let clock = ContinuousClock()
        let reloadStart = clock.now
        await state.reloadWorkspace()
        print("1600-asset / 5-folder reload: \(reloadStart.duration(to: clock.now))")

        let selectionStart = clock.now
        for folder in fixture.folderNames {
            state.toggleFolderSelection(in: fixture.libraryID, relativePath: folder)
        }
        print("1600-asset / 5-folder selection: \(selectionStart.duration(to: clock.now))")
        for _ in 0..<1_000 where state.isMatchingImageContent {
            await Task.yield()
        }
        #expect(!state.isMatchingImageContent)

        let firstReadStart = clock.now
        let rows = state.visibleCompareRows
        print("1600-asset / 5-folder first visible rows read: \(firstReadStart.duration(to: clock.now))")
        #expect(rows.count == 380)
        #expect(rows.allSatisfy { $0.count == 5 })
        #expect(rows.flatMap { $0 }.filter { $0 == nil }.count == 300)
        let displayedIDs = rows.flatMap { $0.compactMap { $0?.id } }
        #expect(displayedIDs.count == 1_600)
        #expect(Set(displayedIDs) == Set(fixture.snapshot.assets.map(\.id)))

        let expectedNames = (0..<230).flatMap { index -> [String] in
            let stem = String(format: "image%05d", index)
            return (index < 50 ? [1, 2, 3, 10] : [1]).map { "\(stem)_\($0).png" }
        }
        #expect(rows.map { $0.compactMap { $0?.filename }.first } == expectedNames)
        #expect(rows.prefix(4).map { $0.map { $0?.filename } } == [
            Array(repeating: "image00000_1.png", count: 5),
            [nil, nil, nil, "image00000_2.png", "image00000_2.png"],
            [nil, nil, "image00000_3.png", "image00000_3.png", "image00000_3.png"],
            [nil, "image00000_10.png", "image00000_10.png", "image00000_10.png", "image00000_10.png"],
        ])

        let selectedRow = try #require(rows.first { row in
            row.last.flatMap { $0 }?.filename == "image00019_2.png"
        })
        let selectedAsset = try #require(selectedRow.last.flatMap { $0 })
        let expectedScrollTarget = try #require(selectedRow.compactMap(\.self).first?.id)
        state.select(assetID: selectedAsset.id)
        #expect(state.currentCompareGroupScrollTargetAssetID == expectedScrollTarget)

        let firstMissingReadStart = clock.now
        let missing = state.missingCompareGroups
        print("1600-asset / 5-folder first missing groups read: \(firstMissingReadStart.duration(to: clock.now))")
        #expect(missing.count == 150)
        #expect(missing.reduce(0) { $0 + $1.missingFolderPaths.count } == 300)

        // Timing is reported, not asserted: elapsed-time thresholds are machine/load dependent.
        // Count checks keep the result consumed and catch caches returning incomplete/stale data.
        let repeats = 10
        #expect(measureReads("visibleCompareRows", repeats: repeats) {
            state.visibleCompareRows.count
        } == 380 * repeats)
        #expect(measureReads("missingCompareGroups", repeats: repeats) {
            state.missingCompareGroups.count
        } == 150 * repeats)
        #expect(measureReads("currentCompareGroupScrollTargetAssetID", repeats: repeats) {
            state.currentCompareGroupScrollTargetAssetID == expectedScrollTarget ? 1 : 0
        } == repeats)
        #expect(state.visibleCompareRows.map { $0.map { $0?.id } } == rows.map { $0.map { $0?.id } })
    }

    private func measureReads(_ label: String, repeats: Int, read: () -> Int) -> Int {
        let clock = ContinuousClock()
        let start = clock.now
        var checksum = 0
        for _ in 0..<repeats {
            checksum += read()
        }
        print("1600-asset / 5-folder \(label), \(repeats) reads: \(start.duration(to: clock.now))")
        return checksum
    }
}

private func makeFiveFolderFixture() -> (snapshot: WorkspaceSnapshot, folderNames: [String], libraryID: UUID) {
    let library = LibraryFolder(displayName: "1600张五目录性能回归", path: "/tmp/phototriage-state-benchmark", columnIndex: 0)
    let folders = ["A-original", "B-result", "C-result", "D-result", "E-result"]
    let assets = folders.enumerated().flatMap { column, folder in
        (0..<230).flatMap { index -> [AssetRecord] in
            let stem = String(format: "image%05d", index)
            var sequences = [1]
            if index < 50 {
                if column >= 1 { sequences.append(10) }
                if column >= 2 { sequences.append(3) }
                if column >= 3 { sequences.append(2) }
            }
            return sequences.map { sequence in
                let filename = "\(stem)_\(sequence).png"
                return AssetRecord(
                    libraryID: library.id, filename: filename, relativePath: "\(folder)/\(filename)",
                    format: .png, fileSizeBytes: 100, width: 100, height: 100
                )
            }
        }
    }
    let snapshot = WorkspaceSnapshot(
        libraries: [library], assets: assets, compareGroups: [],
        keepFolderPath: "/tmp/phototriage-state-benchmark/Keep",
        rejectFolderPath: "/tmp/phototriage-state-benchmark/Reject"
    )
    return (snapshot, folders, library.id)
}

private struct PerformanceSnapshotIndexingService: IndexingService {
    let snapshot: WorkspaceSnapshot

    func loadWorkspace() async throws -> WorkspaceSnapshot {
        snapshot
    }
}

private struct PerformanceEmptyFingerprintService: ImageContentFingerprinting {
    func fingerprints(for requests: [ImageContentFingerprintRequest]) async -> [UUID: ImageContentFingerprint] {
        [:]
    }
}
