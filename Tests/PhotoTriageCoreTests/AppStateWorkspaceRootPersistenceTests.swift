import Foundation
import PhotoTriageCore
import Testing

@MainActor
struct AppStateWorkspaceRootPersistenceTests {
    @Test
    func useWorkspaceRootsDoesNotPersistSelectionAndClearingResetsIt() async throws {
        let store = InMemoryWorkspaceRootsStore()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: makePersistenceSnapshot()),
            workspaceRootsStore: store,
            indexingServiceFactory: { _ in StaticIndexingService(snapshot: makePersistenceSnapshot()) }
        )

        await state.useWorkspaceRoots(["/Photos/A", "/Photos/B"])
        #expect(store.savedRootPaths == nil)

        await state.useWorkspaceRoots([])
        #expect(store.savedRootPaths == nil)
    }

    @Test
    func clearSessionCachesClearsRootsAndDecisions() async throws {
        let store = InMemoryWorkspaceRootsStore(savedRootPaths: ["/Photos/A"])
        let decisionStore = InMemoryDecisionStore()
        decisionStore.decisions = [
            "key": PersistedAssetDecision(ratingState: .keep, appTags: [], finderTags: [])
        ]
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: makePersistenceSnapshot()),
            workspaceRootsStore: store,
            decisionStore: decisionStore
        )

        state.clearSessionCaches()

        #expect(store.savedRootPaths == nil)
        #expect(decisionStore.decisions.isEmpty)
    }

    @Test
    func bootstrapIfNeededIgnoresPersistedRootsForSessionOnlyStartup() async throws {
        let persistedRoots = ["/Persisted/Originals", "/Persisted/Retouched"]
        let store = InMemoryWorkspaceRootsStore(savedRootPaths: persistedRoots)
        let factory = RecordingIndexingServiceFactory()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: makePersistenceSnapshot(libraryName: "mock")),
            workspaceRootsStore: store,
            indexingServiceFactory: factory.makeService(rootPaths:)
        )

        await state.bootstrapIfNeeded()

        #expect(factory.createdRootPaths.isEmpty)
        #expect(state.libraries.map(\.displayName) == ["mock/Originals", "mock/Retouched"])
    }

    @Test
    func bootstrapIfNeededLoadsExplicitPreferredStartupRoots() async throws {
        let startupRoots = ["/Explicit/Originals", "/Explicit/Retouched"]
        let store = InMemoryWorkspaceRootsStore(savedRootPaths: ["/Persisted/Originals"])
        let factory = RecordingIndexingServiceFactory()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: makePersistenceSnapshot(libraryName: "mock")),
            workspaceRootsStore: store,
            indexingServiceFactory: factory.makeService(rootPaths:),
            preferredStartupRoots: startupRoots
        )

        await state.bootstrapIfNeeded()

        #expect(factory.createdRootPaths == [startupRoots])
        #expect(state.libraries.map(\.displayName) == ["Persisted/Originals", "Persisted/Retouched"])
    }

    @Test
    func bootstrapIfNeededUsesEmptyPreferredStartupRootsForColdStart() async throws {
        let factory = RecordingIndexingServiceFactory()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: makePersistenceSnapshot(libraryName: "mock")),
            indexingServiceFactory: factory.makeService(rootPaths:),
            preferredStartupRoots: []
        )

        await state.bootstrapIfNeeded()

        #expect(factory.createdRootPaths == [[]])
    }

    @Test
    func importWorkspaceFoldersFromDroppedURLsKeepsOnlyDirectoriesAndDeduplicatesPaths() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let folderA = tempRoot.appendingPathComponent("A", isDirectory: true)
        let folderB = tempRoot.appendingPathComponent("B", isDirectory: true)
        let file = tempRoot.appendingPathComponent("note.txt")
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: file)

        let store = InMemoryWorkspaceRootsStore()
        let factory = RecordingIndexingServiceFactory()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: makePersistenceSnapshot(libraryName: "mock")),
            workspaceRootsStore: store,
            indexingServiceFactory: factory.makeService(rootPaths:)
        )

        await state.importWorkspaceFolders(from: [folderA, file, folderA, folderB])

        let expectedPaths = [folderA.path, folderB.path]
        #expect(store.savedRootPaths == nil)
        #expect(factory.createdRootPaths == [expectedPaths])
    }

    @Test
    func importWorkspaceFoldersFromDroppedURLsNoOpsWhenNoDirectoriesExist() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let file = tempRoot.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: file)

        let store = InMemoryWorkspaceRootsStore(savedRootPaths: ["/Persisted/A"])
        let factory = RecordingIndexingServiceFactory()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: makePersistenceSnapshot(libraryName: "mock")),
            workspaceRootsStore: store,
            indexingServiceFactory: factory.makeService(rootPaths:)
        )

        await state.importWorkspaceFolders(from: [file])

        #expect(store.savedRootPaths == ["/Persisted/A"])
        #expect(factory.createdRootPaths.isEmpty)
    }

    @Test
    func importWorkspaceFoldersFromDroppedURLsReturnsWorkspaceToGridMode() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let folder = tempRoot.appendingPathComponent("A", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let state = AppState(
            indexingService: StaticIndexingService(snapshot: makePersistenceSnapshot(libraryName: "mock")),
            indexingServiceFactory: { _ in StaticIndexingService(snapshot: makePersistenceSnapshot(libraryName: "Imported")) }
        )
        state.mode = .compare

        await state.importWorkspaceFolders(from: [folder])

        #expect(state.mode == .grid)
        #expect(state.libraries.map(\.displayName) == ["Imported/Originals", "Imported/Retouched"])
    }

    @Test
    func useSampleWorkspaceLoadsFixtureDataAfterEmptyStartupRoots() async throws {
        let store = InMemoryWorkspaceRootsStore(savedRootPaths: ["/Photos/Previous"])
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: makePersistenceSnapshot(libraryName: "mock")),
            workspaceRootsStore: store,
            indexingServiceFactory: { _ in StaticIndexingService(snapshot: emptyPersistenceSnapshot()) },
            preferredStartupRoots: []
        )

        await state.bootstrapIfNeeded()
        #expect(state.libraries.isEmpty)

        await state.useSampleWorkspace()

        #expect(store.savedRootPaths == nil)
        #expect(state.mode == .grid)
        #expect(state.libraries.map(\.displayName) == ["原始图", "AI 精修", "交付版"])
        #expect(state.assets.map(\.filename).contains("look-001.CR2"))
    }

    @Test
    func assetDecisionsPersistThroughDecisionStoreDuringSession() async throws {
        let decisionStore = InMemoryDecisionStore()
        let snapshot = makePersistenceSnapshot()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: snapshot),
            decisionStore: decisionStore
        )

        await state.reloadWorkspace()
        let assetID = try #require(state.assets.first?.id)
        state.applyRating(.keep, to: [assetID])

        let reloaded = AppState(
            indexingService: StaticIndexingService(snapshot: snapshot),
            decisionStore: decisionStore
        )
        await reloaded.reloadWorkspace()

        #expect(reloaded.assets.first?.ratingState == .keep)
        #expect(!decisionStore.decisions.isEmpty)
    }

    @Test
    func resettingRatingRemovesPersistedSessionDecision() async throws {
        let decisionStore = InMemoryDecisionStore()
        let snapshot = makePersistenceSnapshot()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: snapshot),
            decisionStore: decisionStore
        )

        await state.reloadWorkspace()
        let assetID = try #require(state.assets.first?.id)
        state.applyRating(.keep, to: [assetID])
        state.applyRating(.pending, to: [assetID])

        let reloaded = AppState(
            indexingService: StaticIndexingService(snapshot: snapshot),
            decisionStore: decisionStore
        )
        await reloaded.reloadWorkspace()

        #expect(reloaded.assets.first?.ratingState == .pending)
        #expect(decisionStore.decisions.isEmpty)
    }

    @Test
    func reloadWorkspacePreservesSessionDecisionsAndTags() async throws {
        let snapshot = makePersistenceSnapshot()
        let service = MutableIndexingService(snapshot: snapshot)
        let state = AppState(indexingService: service)

        await state.reloadWorkspace()
        let assetID = try #require(state.assets.first?.id)
        state.applyRating(.keep, to: [assetID])
        state.appendTag("精选", to: [assetID])

        service.snapshot = makePersistenceSnapshot()
        await state.reloadWorkspace()

        #expect(state.assets.first?.ratingState == .keep)
        #expect(state.assets.first?.appTags.map(\.name) == ["精选"])
    }

    @Test
    func reloadWorkspacePreservesSessionDecisionsWhenFileSizeChanges() async throws {
        let snapshot = makePersistenceSnapshot(fileSizeBytes: 100)
        let service = MutableIndexingService(snapshot: snapshot)
        let state = AppState(indexingService: service)

        await state.reloadWorkspace()
        let assetID = try #require(state.assets.first?.id)
        state.applyRating(.reject, to: [assetID])
        state.appendTag("已筛", to: [assetID])

        service.snapshot = makePersistenceSnapshot(fileSizeBytes: 250)
        await state.reloadWorkspace()

        #expect(state.assets.first?.fileSizeBytes == 250)
        #expect(state.assets.first?.ratingState == .reject)
        #expect(state.assets.first?.appTags.map(\.name) == ["已筛"])
    }

    @Test
    func assetMutationsUpdateVisibleSnapshotImmediately() async throws {
        let snapshot = makePersistenceSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        let assetID = try #require(state.assets.first?.id)

        state.applyRating(.keep, to: [assetID])
        state.appendTag("精选", to: [assetID])
        state.rotateAssets([assetID], quarterTurns: 1)

        #expect(state.filteredAssets.first?.ratingState == .keep)
        #expect(state.filteredAssets.first?.appTags.map(\.name) == ["精选"])
        #expect(state.filteredAssets.first?.rotationDegrees == 90)
    }

    @Test
    func scheduledAutoRefreshReindexesWithoutInvalidatingUnchangedImages() async throws {
        let snapshot = makePersistenceSnapshot()
        let service = CountingIndexingService(snapshot: snapshot)
        let watcherFactory = RecordingWorkspaceFileWatcherFactory()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: snapshot),
            indexingServiceFactory: { _ in service },
            workspaceFileWatcherFactory: watcherFactory.makeWatcher(rootPaths:onChange:)
        )

        await state.useWorkspaceRoots(["/Photos/Originals"])
        let originalRefreshToken = state.imageRefreshToken
        let originalLoadCount = service.loadWorkspaceCallCount

        watcherFactory.triggerChange()
        try await Task.sleep(nanoseconds: 550_000_000)

        #expect(state.imageRefreshToken == originalRefreshToken)
        #expect(service.loadWorkspaceCallCount == originalLoadCount + 1)
        #expect(state.filteredAssets.first?.relativePath == "set-a/cover.jpg")
    }

    @Test
    func reloadWorkspacePreservesSessionRotation() async throws {
        let snapshot = makePersistenceSnapshot()
        let service = MutableIndexingService(snapshot: snapshot)
        let state = AppState(indexingService: service)

        await state.reloadWorkspace()
        let assetID = try #require(state.assets.first?.id)
        state.rotateAssets([assetID], quarterTurns: 1)

        service.snapshot = makePersistenceSnapshot()
        await state.reloadWorkspace()

        #expect(state.assets.first?.rotationDegrees == 90)
    }

    @Test
    func reloadWorkspaceClearsSelectionButPreservesSessionDecisions() async throws {
        let snapshot = makePersistenceSnapshot()
        let service = MutableIndexingService(snapshot: snapshot)
        let state = AppState(indexingService: service)

        await state.reloadWorkspace()
        let assetID = try #require(state.assets.first?.id)
        state.select(assetID: assetID)
        state.applyRating(.keep, to: [assetID])

        await state.reloadWorkspace()

        #expect(state.selectedAssetID == nil)
        #expect(state.selectedAssetIDs.isEmpty)
        #expect(state.assets.first?.ratingState == .keep)
    }

}

private func makePersistenceSnapshot(libraryName: String = "Restored", fileSizeBytes: Int64 = 100) -> WorkspaceSnapshot {
    let libraries = [
        LibraryFolder(displayName: libraryName + "/Originals", path: "/tmp/originals", columnIndex: 0),
        LibraryFolder(displayName: libraryName + "/Retouched", path: "/tmp/retouched", columnIndex: 1),
    ]

    let assets = [
        AssetRecord(
            libraryID: libraries[0].id,
            filename: "cover.jpg",
            relativePath: "set-a/cover.jpg",
            format: .jpg,
            fileSizeBytes: fileSizeBytes,
            width: 1,
            height: 1
        )
    ]

    return WorkspaceSnapshot(
        libraries: libraries,
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: libraries, assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private func emptyPersistenceSnapshot() -> WorkspaceSnapshot {
    WorkspaceSnapshot(
        libraries: [],
        assets: [],
        compareGroups: [],
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private final class InMemoryWorkspaceRootsStore: WorkspaceRootsPersisting, @unchecked Sendable {
    var savedRootPaths: [String]?

    init(savedRootPaths: [String]? = nil) {
        self.savedRootPaths = savedRootPaths
    }

    func clearRootPaths() {
        savedRootPaths = nil
    }
}

private struct RecordingIndexingServiceFactory: Sendable {
    private final class Storage: @unchecked Sendable {
        var createdRootPaths: [[String]] = []
    }

    private let storage = Storage()

    var createdRootPaths: [[String]] { storage.createdRootPaths }

    func makeService(rootPaths: [String]) -> any IndexingService {
        storage.createdRootPaths.append(rootPaths)
        return StaticIndexingService(snapshot: makePersistenceSnapshot(libraryName: "Persisted"))
    }
}

private struct StaticIndexingService: IndexingService {
    let snapshot: WorkspaceSnapshot

    func loadWorkspace() async throws -> WorkspaceSnapshot {
        snapshot
    }
}

private final class MutableIndexingService: IndexingService, @unchecked Sendable {
    var snapshot: WorkspaceSnapshot

    init(snapshot: WorkspaceSnapshot) {
        self.snapshot = snapshot
    }

    func loadWorkspace() async throws -> WorkspaceSnapshot {
        snapshot
    }
}

private final class CountingIndexingService: IndexingService, @unchecked Sendable {
    let snapshot: WorkspaceSnapshot
    var loadWorkspaceCallCount = 0

    init(snapshot: WorkspaceSnapshot) {
        self.snapshot = snapshot
    }

    func loadWorkspace() async throws -> WorkspaceSnapshot {
        loadWorkspaceCallCount += 1
        return snapshot
    }
}

private final class RecordingWorkspaceFileWatcherFactory: @unchecked Sendable {
    private var onChange: (@Sendable () -> Void)?

    func makeWatcher(rootPaths: [String], onChange: @escaping @Sendable () -> Void) -> any WorkspaceFileWatching {
        self.onChange = onChange
        return NoopWorkspaceFileWatcher()
    }

    func triggerChange() {
        onChange?()
    }
}

private final class NoopWorkspaceFileWatcher: WorkspaceFileWatching, @unchecked Sendable {
    func start() {}
    func stop() {}
}

private final class InMemoryDecisionStore: AssetDecisionPersisting, @unchecked Sendable {
    var decisions: [String: PersistedAssetDecision] = [:]

    func loadDecisions() -> [String: PersistedAssetDecision] {
        decisions
    }

    func saveDecisions(_ decisions: [String: PersistedAssetDecision]) {
        self.decisions = decisions
    }

    func clearDecisions() {
        decisions = [:]
    }
}
