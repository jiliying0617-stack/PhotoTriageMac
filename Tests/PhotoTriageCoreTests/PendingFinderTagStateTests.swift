import Foundation
import Testing
@testable import PhotoTriageCore

@MainActor
struct PendingFinderTagStateTests {
    let red = FinderTag(name: "红色", color: .red)
    let blue = FinderTag(name: "蓝色", color: .blue)

    @Test func permissionFailurePersistsWithoutBlockingSuccessfulFilesAndRetries() async throws {
        let snapshot = fixture()
        let service = PendingTestTagService()
        service.failures["one.jpg"] = .EPERM
        let store = MemoryPendingFinderTagStore()
        let state = makeState(snapshot, service, store)
        await state.reloadWorkspace()
        let ids = snapshot.assets.map(\.id)
        state.setSelection(assetIDs: Set(ids))
        state.enterCompareMode()
        let order = state.compareSelectionIDs
        await state.toggleExclusiveFinderTagForCompareGroup(red)
        #expect(state.assets.allSatisfy { $0.finderTags == [red] })
        #expect(state.pendingFinderTagCount == 1)
        #expect(state.finderTagErrorMessage == nil)
        #expect(state.assets.first { $0.filename == "two.jpg" }?.finderTagSyncIssue == nil)
        #expect(service.writes.count == 1)
        #expect(try store.load().count == 1)
        #expect(state.compareSelectionIDs == order)

        await state.refreshFinderTagsFromDisk()
        await state.reloadWorkspace(resetPresentation: false)
        #expect(state.assets.first { $0.filename == "one.jpg" }?.finderTags == [red])
        #expect(state.pendingFinderTagCount == 1)

        service.failures = [:]
        await state.retryPendingFinderTags()
        #expect(state.pendingFinderTagCount == 0)
        #expect(try store.load().isEmpty)
        #expect(service.tags["one.jpg"] == [red])
    }

    @Test func replacingAndClearingLocallySurvivesRestartAndSessionCleanup() async throws {
        var snapshot = fixture()
        snapshot.assets[0].finderTags = [blue]
        let service = PendingTestTagService()
        service.failures["one.jpg"] = .ENOTSUP
        let store = MemoryPendingFinderTagStore()
        let state = makeState(snapshot, service, store)
        await state.reloadWorkspace()
        let id = snapshot.assets[0].id
        await state.toggleExclusiveFinderTag(red, for: [id])
        await state.toggleExclusiveFinderTag(blue, for: [id])
        #expect(state.assets[0].finderTags == [blue])
        await state.toggleExclusiveFinderTag(blue, for: [id])
        #expect(state.assets[0].finderTags.isEmpty)
        #expect(state.pendingFinderTagCount == 1)
        // Only the first action probes the unsupported file; subsequent keypresses
        // update local metadata immediately until an explicit retry is requested.
        #expect(service.attempts == 1)
        state.clearSessionCaches()
        let restarted = makeState(snapshot, service, store)
        await restarted.reloadWorkspace()
        #expect(restarted.assets[0].finderTags.isEmpty)
        #expect(restarted.assets[0].finderTagSyncIssue != nil)
        #expect(try store.load().values.first?.tags == [])
        service.failures = [:]
        await restarted.retryPendingFinderTags()
        #expect(service.tags["one.jpg"] == [])
        #expect(restarted.pendingFinderTagCount == 0)
    }

    @Test func missingFileIsNotReportedAsLocallyTaggedAndOtherFileStillSucceeds() async throws {
        let snapshot = fixture()
        let service = PendingTestTagService()
        service.failures["one.jpg"] = .ENOENT
        let store = MemoryPendingFinderTagStore()
        let state = makeState(snapshot, service, store)
        await state.reloadWorkspace()
        await state.replaceFinderTags(with: [red], for: snapshot.assets.map(\.id))
        #expect(state.assets[0].finderTags.isEmpty)
        #expect(state.assets[1].finderTags == [red])
        #expect(state.pendingFinderTagCount == 0)
        #expect(state.finderTagErrorMessage?.contains("one.jpg") == true)
        #expect(try store.load().isEmpty)
    }

    @Test func localStoreFailureDoesNotWriteFilesOrClaimSuccess() async {
        let snapshot = fixture()
        let service = PendingTestTagService()
        let state = makeState(snapshot, service, UnwritablePendingStore())
        await state.reloadWorkspace()
        await state.replaceFinderTags(with: [red], for: snapshot.assets.map(\.id))
        #expect(service.attempts == 0)
        #expect(state.assets.allSatisfy { $0.finderTags.isEmpty })
        #expect(state.pendingFinderTagCount == 0)
        #expect(state.finderTagErrorMessage?.contains("保存失败") == true)
    }

    @Test func savedColorAppearsInSearchAndColorCounts() async {
        let snapshot = fixture()
        let service = PendingTestTagService()
        service.failures["one.jpg"] = .EROFS
        let state = makeState(snapshot, service, MemoryPendingFinderTagStore())
        await state.reloadWorkspace()
        await state.replaceFinderTags(with: [red], for: [snapshot.assets[0].id])
        #expect(state.finderTagColorSummary.count(for: .red) == 1)
        state.searchText = "红色"
        #expect(state.filteredAssets.map(\.filename) == ["one.jpg"])
    }

    @Test func knownFailuresOnlyAllowFallback() {
        for code: POSIXErrorCode in [.EPERM, .EACCES, .EROFS, .ENOTSUP, .EOPNOTSUPP, .ENOSYS] {
            #expect(FinderTagWriteFailure.localFallbackReason(for: POSIXError(code)) != nil)
        }
        for code: POSIXErrorCode in [.ENOENT, .EIO, .ENOSPC] {
            #expect(FinderTagWriteFailure.localFallbackReason(for: POSIXError(code)) == nil)
        }
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 0, userInfo: [NSUnderlyingErrorKey: POSIXError(.EPERM)])
        #expect(FinderTagWriteFailure.localFallbackReason(for: wrapped) != nil)
    }

    private func makeState(_ snapshot: WorkspaceSnapshot, _ service: PendingTestTagService,
                           _ store: any PendingFinderTagPersisting) -> AppState {
        AppState(indexingService: PendingTagIndex(snapshot: snapshot), finderTagService: service,
                 pendingFinderTagStore: store)
    }

    @Test func jsonBackedPendingTagsRestoreAfterAppStateRecreation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = root.appendingPathComponent("pending.json")
        let snapshot = fixture()
        let service = PendingTestTagService()
        service.failures["one.jpg"] = .EPERM
        let state = makeState(snapshot, service, JSONPendingFinderTagStore(fileURL: record))
        await state.reloadWorkspace()
        await state.replaceFinderTags(with: [red], for: [snapshot.assets[0].id])
        state.clearSessionCaches()

        let restarted = makeState(snapshot, service, JSONPendingFinderTagStore(fileURL: record))
        await restarted.reloadWorkspace()
        #expect(restarted.assets[0].finderTags == [red])
        #expect(restarted.pendingFinderTagCount == 1)
    }

    @Test func legacyAssetJSONDecodesWithoutSyncIssue() throws {
        let asset = fixture().assets[0]
        let encoded = try JSONEncoder().encode(asset)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "finderTagSyncIssue")
        let legacy = try JSONDecoder().decode(AssetRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.finderTagSyncIssue == nil)
        #expect(legacy.id == asset.id)
    }

    @Test func rapidRepeatedColorToggleKeepsInputOrderWhileNetworkWriteIsPending() async throws {
        let snapshot = fixture()
        let service = PendingTestTagService()
        service.failures["one.jpg"] = .EPERM
        let store = MemoryPendingFinderTagStore()
        let state = makeState(snapshot, service, store)
        await state.reloadWorkspace()
        let id = snapshot.assets[0].id
        let first = Task { await state.toggleExclusiveFinderTag(red, for: [id]) }
        await Task.yield()
        let second = Task { await state.toggleExclusiveFinderTag(red, for: [id]) }
        await first.value
        await second.value
        #expect(state.assets[0].finderTags.isEmpty)
        #expect(try store.load().values.first?.tags.isEmpty == true)
        #expect(state.pendingFinderTagCount == 1)
    }

    private func fixture() -> WorkspaceSnapshot {
        let library = LibraryFolder(displayName: "NFS", path: "/tmp/test-network", columnIndex: 0)
        let assets = ["one.jpg", "two.jpg"].map {
            AssetRecord(libraryID: library.id, filename: $0, relativePath: $0,
                        format: .jpg, fileSizeBytes: 1, width: 100, height: 100)
        }
        return WorkspaceSnapshot(libraries: [library], assets: assets, compareGroups: [], keepFolderPath: "", rejectFolderPath: "")
    }
}

private struct PendingTagIndex: IndexingService {
    let snapshot: WorkspaceSnapshot
    func loadWorkspace() async throws -> WorkspaceSnapshot { snapshot }
}

private final class PendingTestTagService: FinderTagSyncing, @unchecked Sendable {
    var failures: [String: POSIXErrorCode] = [:]
    var tags: [String: [FinderTag]] = [:]
    var writes: [String] = []
    var attempts = 0
    private let lock = NSLock()
    func readTags(at url: URL) throws -> [FinderTag] {
        lock.withLock { tags[url.lastPathComponent] ?? [] }
    }
    func writeTags(_ updated: [FinderTag], at url: URL) throws {
        try lock.withLock {
            attempts += 1
            if let failure = failures[url.lastPathComponent] { throw POSIXError(failure) }
            tags[url.lastPathComponent] = updated
            writes.append(url.lastPathComponent)
        }
    }
}

private struct UnwritablePendingStore: PendingFinderTagPersisting {
    func load() throws -> [String: PendingFinderTagEdit] { [:] }
    func apply(updates: [String: PendingFinderTagEdit], removingKeys: Set<String>) throws { throw POSIXError(.ENOSPC) }
}
