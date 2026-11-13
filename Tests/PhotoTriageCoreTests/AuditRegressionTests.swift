import Foundation
import ImageIO
import Testing
@testable import PhotoTriageCore

@MainActor
struct AuditRegressionTests {
    @Test func sparseReferenceKeepsOtherFoldersInOneRow() async throws {
        let state = AppState(indexingService: RegressionIndex(snapshot: regressionSnapshot([
            "A/001.png", "B/001.png", "C/001.png", "B/002.png", "C/002.png"
        ])), imageContentFingerprintService: RegressionFingerprints(empty: true))
        await state.reloadWorkspace()
        try await finishMatching(state)
        #expect(state.visibleCompareRows.count == 2)
        #expect(state.missingCompareAssetCount == 1)
        #expect(state.visibleCompareRows.last?.map { $0?.relativePath } == [nil, "B/002.png", "C/002.png"])
    }

    @Test func visualMatchingFillsAlreadyOpenCompareSlotsWithoutMovingFocus() async throws {
        let state = AppState(indexingService: RegressionIndex(snapshot: regressionSnapshot(["A/source.png", "B/result.png"])),
            imageContentFingerprintService: RegressionFingerprints(delay: 80_000_000))
        await state.reloadWorkspace()
        state.jumpToBasenameCompareGroup(number: 1)
        let focus = state.compareSession.focusedAssetID
        try await finishMatching(state)
        #expect(state.comparePaneAssets.compactMap { $0 }.count == 2)
        #expect(state.compareSession.focusedAssetID == focus)
        #expect(state.compareSession.folderPaths == ["A", "B"])
    }

    @Test func missingReferenceAlsoSupportsContentPairingBetweenOtherColumns() async throws {
        let snapshot = regressionSnapshot(["A/001.png", "B/001.png", "C/001.png", "B/source.png", "C/result.png"])
        let state = AppState(indexingService: RegressionIndex(snapshot: snapshot),
            imageContentFingerprintService: RegressionFingerprints())
        await state.reloadWorkspace()
        try await finishMatching(state)
        #expect(state.visibleCompareRows.count == 2)
        #expect(state.missingCompareAssetCount == 1)
    }

    @Test func repeatedEquivalentFingerprintsExceedOriginalShortlist() {
        let references = (0..<25).map { _ in UUID() }
        let targets = (0..<25).map { _ in UUID() }
        let prints = Dictionary(uniqueKeysWithValues: (references + targets).map { ($0, regressionFingerprint(100)) })
        let matches = ImageContentMatcher.bestMatches(referenceAssetIDs: references, targetAssetIDs: targets, fingerprints: prints)
        #expect(matches.count == 25)
        #expect(Set(matches.values).count == 25)
    }

    @Test func candidateConflictIsReassignedInsteadOfReportingMissing() {
        let a = UUID(), b = UUID(), x = UUID(), y = UUID()
        let prints = [a: regressionFingerprint(51), b: regressionFingerprint(255), x: regressionFingerprint(76), y: regressionFingerprint(0)]
        let matches = ImageContentMatcher.bestMatches(referenceAssetIDs: [a, b], targetAssetIDs: [x, y], fingerprints: prints)
        #expect(matches[a] == y)
        #expect(matches[b] == x)
    }

    @Test func rapidExclusiveTagsPreserveInputOrderAndRepeatedColorTogglesOff() async throws {
        let state = AppState(indexingService: RegressionIndex(snapshot: regressionSnapshot(["one.png"])), finderTagService: RegressionSlowTags())
        await state.reloadWorkspace()
        let ids = state.assets.map(\.id)
        let red = FinderTag(name: "红色", color: .red)
        let orange = FinderTag(name: "橙色", color: .orange)
        let first = Task { await state.toggleExclusiveFinderTag(red, for: ids) }
        try await Task.sleep(for: .milliseconds(15))
        let second = Task { await state.toggleExclusiveFinderTag(orange, for: ids) }
        await first.value
        await second.value
        #expect(state.assets[0].finderTags == [orange])
        let third = Task { await state.toggleExclusiveFinderTag(red, for: ids) }
        try await Task.sleep(for: .milliseconds(15))
        let fourth = Task { await state.toggleExclusiveFinderTag(red, for: ids) }
        await third.value
        await fourth.value
        #expect(state.assets[0].finderTags.isEmpty)
        #expect(!state.isUpdatingFinderTags)
    }

    @Test func sameFileRotationsNeverOverlap() async throws {
        let rotation = RegressionRotation()
        let state = AppState(indexingService: RegressionIndex(snapshot: regressionSnapshot(["one.png"])), assetFileRotationService: rotation)
        await state.reloadWorkspace()
        let ids = state.assets.map(\.id)
        let first = Task { await state.rotateLocalAssetFiles(ids) }
        try await Task.sleep(for: .milliseconds(15))
        let second = Task { await state.rotateLocalAssetFiles(ids) }
        await first.value
        await second.value
        #expect(rotation.maximumActive == 1)
        #expect(!state.isRotatingLocalFiles)
    }

    @Test func independentFilesCanAcquireGateWhileOverlappingFilesWait() async {
        let gate = FileMutationGate()
        let a = UUID(), b = UUID()
        await gate.acquire([a])
        var acquiredA = false
        let waiting = Task { await gate.acquire([a]); acquiredA = true; gate.release([a]) }
        await Task.yield()
        await gate.acquire([b])
        #expect(!acquiredA)
        gate.release([b])
        gate.release([a])
        await waiting.value
        #expect(acquiredA)
    }

    @Test func exportPartialFailureAndRetryAreIdempotent() async throws {
        let root = try regressionDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        let output = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("good".utf8).write(to: source.appendingPathComponent("good.png"))
        let snapshot = regressionSnapshot(["good.png", "missing.png"], root: source.path)
        let request = ExportRequest(libraries: snapshot.libraries, assets: snapshot.assets,
            keepFolderPath: output.path, rejectFolderPath: output.path, pendingFolderPath: output.path, includePending: true)
        let first = try await FileSystemExportService().export(request)
        #expect(first.exportedCount == 1)
        #expect(first.failures.count == 1)
        let second = try await FileSystemExportService().export(request)
        #expect(second.exportedCount == 0)
        #expect(second.skippedCount == 1)
        #expect(second.failures.count == 1)
        #expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent("good 2.png").path))
        try Data("fixed".utf8).write(to: source.appendingPathComponent("missing.png"))
        let third = try await FileSystemExportService().export(request)
        #expect(third.exportedCount == 1)
        #expect(third.skippedCount == 1)
        #expect(third.failures.isEmpty)
        #expect(third.receiptPath != nil)
    }

    @Test func cancelledExportDoesNotCopySources() async throws {
        let root = try regressionDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = regressionSnapshot(["missing.png"])
        let request = ExportRequest(libraries: snapshot.libraries, assets: snapshot.assets,
            keepFolderPath: root.path, rejectFolderPath: root.path, pendingFolderPath: root.path, includePending: true)
        let task = Task { try await FileSystemExportService().export(request) }
        task.cancel()
        let summary = try await task.value
        #expect(summary.wasCancelled)
        #expect(summary.exportedCount == 0)
    }

    @Test func incrementalRefreshAddsRemovesAndPreservesUntouchedRecords() async throws {
        let root = try regressionDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("one.png")
        let second = root.appendingPathComponent("two.png")
        try Data("one".utf8).write(to: first)
        let service = FileSystemIndexingService(rootPaths: [root.path])
        let initial = try await service.loadWorkspace()
        try Data("two".utf8).write(to: second)
        let added = try await service.refreshWorkspace(initial, changedPaths: [second.path])
        #expect(added.assets.map(\.filename) == ["one.png", "two.png"])
        #expect(added.assets[0].id == initial.assets[0].id)
        try FileManager.default.removeItem(at: first)
        let removed = try await service.refreshWorkspace(added, changedPaths: [first.path])
        #expect(removed.assets.map(\.filename) == ["two.png"])
    }

    @Test func fileBackupRestoresExactBytes() throws {
        let root = try regressionDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.bin")
        let original = Data((0..<255).map(UInt8.init))
        try original.write(to: url)
        let backup = try FileMutationBackup(urls: [url])
        defer { backup.discard() }
        try Data("changed".utf8).write(to: url)
        try backup.restore()
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func largeSelectionUsesStableVisibleOrder() async {
        let snapshot = regressionSnapshot((0..<3000).reversed().map { String(format: "%05d.png", $0) })
        let state = AppState(indexingService: RegressionIndex(snapshot: snapshot))
        await state.reloadWorkspace()
        state.setSelection(assetIDs: Set(state.assets.map(\.id)))
        #expect(state.selectedAssetIDs.count == 3000)
        #expect(state.focusedAssetIDs.first == state.filteredAssets.first?.id)
    }
}

private struct RegressionIndex: IndexingService {
    let snapshot: WorkspaceSnapshot
    func loadWorkspace() async throws -> WorkspaceSnapshot { snapshot }
}
private struct RegressionFingerprints: ImageContentFingerprinting {
    var empty = false
    var delay: UInt64 = 0
    func fingerprints(for requests: [ImageContentFingerprintRequest]) async -> [UUID: ImageContentFingerprint] {
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        return empty ? [:] : Dictionary(uniqueKeysWithValues: requests.map { ($0.assetID, regressionFingerprint(100)) })
    }
}
private func regressionFingerprint(_ value: UInt8) -> ImageContentFingerprint {
    ImageContentFingerprint(edgeWords: [0, 0, 0, 0], normalizedLuminance: [UInt8](repeating: value, count: 256),
        meanRed: 128, meanGreen: 128, meanBlue: 128, luminanceDeviation: 30, aspectRatio: 1)
}
private func regressionSnapshot(_ paths: [String], root: String = "/nonexistent/PhotoTriageRegression") -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "Regression", path: root, columnIndex: 0)
    let assets = paths.map { AssetRecord(libraryID: library.id, filename: URL(fileURLWithPath: $0).lastPathComponent,
        relativePath: $0, format: .png, fileSizeBytes: 100, width: 256, height: 192) }
    return WorkspaceSnapshot(libraries: [library], assets: assets, compareGroups: [], keepFolderPath: "/tmp/Keep", rejectFolderPath: "/tmp/Reject")
}
private func regressionDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoTriageRegression-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
@MainActor private func finishMatching(_ state: AppState) async throws {
    for _ in 0..<100 where state.isMatchingImageContent { try await Task.sleep(for: .milliseconds(10)) }
    #expect(!state.isMatchingImageContent)
}
private struct RegressionSlowTags: FinderTagSyncing {
    func readTags(at url: URL) throws -> [FinderTag] { [] }
    func writeTags(_ tags: [FinderTag], at url: URL) throws {
        Thread.sleep(forTimeInterval: tags.first?.color == .red ? 0.08 : 0.005)
    }
}
private final class RegressionRotation: AssetFileRotating, @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var maximum = 0
    var maximumActive: Int { lock.lock(); defer { lock.unlock() }; return maximum }
    func rotateFile(at url: URL, quarterTurns: Int) throws {
        lock.lock(); active += 1; maximum = max(maximum, active); lock.unlock()
        Thread.sleep(forTimeInterval: 0.08)
        lock.lock(); active -= 1; lock.unlock()
    }
}
