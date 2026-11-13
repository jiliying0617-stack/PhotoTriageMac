import Foundation
import Testing
@testable import PhotoTriageCore

@MainActor
struct ComparisonCacheTests {
    @Test func warmedRowsRefreshWhenContentMatchingFinishes() async throws {
        let snapshot = fixture(["A/source.png", "B/result.png"])
        let fingerprints = ControlledFingerprints()
        let state = AppState(indexingService: CacheIndex(snapshot: snapshot), imageContentFingerprintService: fingerprints)
        await state.reloadWorkspace()
        #expect(state.isMatchingImageContent)
        #expect(state.visibleCompareRows.first?.map { $0?.filename } == ["source.png", nil])
        #expect(state.missingCompareAssetCount == 0)
        await fingerprints.release()
        try await eventually { !state.isMatchingImageContent }
        #expect(state.visibleCompareRows.first?.map { $0?.filename } == ["source.png", "result.png"])
        #expect(state.visibleCompleteCompareRows.count == 1)
        #expect(state.missingCompareGroups.isEmpty)
    }

    @Test func warmedRecordsRefreshDimensionsWithoutChangingRows() async throws {
        let snapshot = fixture(["A/one.png", "B/one.png", "A/two.png"], size: 0)
        let metadata = ControlledMetadata()
        let state = AppState(indexingService: CacheIndex(snapshot: snapshot, metadata: metadata))
        await state.reloadWorkspace()
        let rows = state.visibleCompareRows.map { $0.map { $0?.id } }
        let missing = try #require(state.missingCompareGroups.first?.presentAssets.first)
        #expect(missing.width == 0)
        state.select(assetID: missing.id)
        await metadata.release()
        try await eventually { state.selectedAsset?.width == 800 }
        #expect(state.visibleCompareRows.map { $0.map { $0?.id } } == rows)
        #expect(state.missingCompareGroups.first?.presentAssets.first?.width == 800)
        #expect(state.missingCompareGroups.first?.slots.compactMap(\.self).first?.height == 600)
        #expect(state.filteredAssets.first { $0.id == missing.id }?.width == 800)
        #expect(state.basenameCompareGroups.flatMap { $0 }.first { $0.id == missing.id }?.height == 600)
        #expect(state.currentBasenameCompareGroupNumber == 2)
    }

    @Test func warmedCachesInvalidateOnRatingsFiltersAndFolderChanges() async throws {
        let snapshot = fixture(["A/one.png", "B/one.png", "A/two.png", "C/two.png"])
        let state = AppState(indexingService: CacheIndex(snapshot: snapshot))
        await state.reloadWorkspace()
        let library = try #require(snapshot.libraries.first)
        state.selectFolder(in: library.id, relativePath: "A")
        state.toggleFolderSelection(in: library.id, relativePath: "B")
        let selected = try #require(state.visibleCompareRows.first?.first.flatMap { $0 })
        _ = state.missingCompareGroups
        state.applyRating(.keep, to: [selected.id])
        #expect(state.visibleCompareRows.first?.first.flatMap { $0 }?.ratingState == .keep)
        state.selectCategoryFilter(.rating(.keep))
        #expect(state.visibleCompareRows.count == 1)
        // Scope diagnostics are not narrowed to the Keep category.
        #expect(state.missingCompareGroups.count == 1)
        state.selectCategoryFilter(.all)
        state.toggleFolderSelection(in: library.id, relativePath: "B")
        state.toggleFolderSelection(in: library.id, relativePath: "C")
        #expect(state.visibleCompareRows.map { $0.map { $0?.relativePath } } == [
            ["A/one.png", nil], ["A/two.png", "C/two.png"]
        ])
    }

    private func fixture(_ paths: [String], size: Int = 100) -> WorkspaceSnapshot {
        let library = LibraryFolder(displayName: "Cache regression", path: "/tmp/phototriage-cache-tests", columnIndex: 0)
        let assets = paths.map { path in
            AssetRecord(libraryID: library.id, filename: URL(fileURLWithPath: path).lastPathComponent,
                        relativePath: path, format: .png, fileSizeBytes: 100, width: size, height: size)
        }
        return WorkspaceSnapshot(libraries: [library], assets: assets, compareGroups: [],
                                 keepFolderPath: "/tmp/Keep", rejectFolderPath: "/tmp/Reject")
    }

    private func eventually(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(predicate())
    }
}

private struct CacheIndex: IndexingService {
    let snapshot: WorkspaceSnapshot
    var metadata: ControlledMetadata? = nil
    func loadWorkspace() async throws -> WorkspaceSnapshot { snapshot }
    func loadMetadata(for assets: [AssetRecord], libraries: [LibraryFolder]) async throws -> [UUID: AssetMetadata] {
        guard let metadata else { return [:] }
        await metadata.wait()
        return Dictionary(uniqueKeysWithValues: assets.map { ($0.id, AssetMetadata(width: 800, height: 600)) })
    }
}

private actor ControlledMetadata {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        released = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

private actor ControlledFingerprints: ImageContentFingerprinting {
    private let gate = ControlledMetadata()
    func release() async { await gate.release() }
    func fingerprints(for requests: [ImageContentFingerprintRequest]) async -> [UUID: ImageContentFingerprint] {
        await gate.wait()
        let fingerprint = ImageContentFingerprint(edgeWords: [0, 0, 0, 0],
            normalizedLuminance: [UInt8](repeating: 100, count: 256),
            meanRed: 128, meanGreen: 128, meanBlue: 128, luminanceDeviation: 30, aspectRatio: 1)
        return Dictionary(uniqueKeysWithValues: requests.map { ($0.assetID, fingerprint) })
    }
}
