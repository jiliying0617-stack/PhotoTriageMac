import Foundation
import PhotoTriageCore
import Testing

struct FileSystemIndexingServiceTests {
    @Test func pOnlyIndexingNeverReadsFinderMetadataDuringLoadOrRefresh() async throws {
        let root = try temporaryDirectory(named: "p-only-index")
        defer { try? FileManager.default.removeItem(at: root) }
        try createFile(named: "photo.jpg", under: root)
        let service = FileSystemIndexingService(rootPaths: [root.path],
            finderTagService: ForbiddenFinderMetadataService(), readsFinderTags: false)
        let snapshot = try await service.loadWorkspace()
        #expect(snapshot.assets.count == 1)
        #expect(snapshot.assets.allSatisfy { $0.finderTags.isEmpty })
        let refreshed = try await service.refreshWorkspace(snapshot, changedPaths: [root.appendingPathComponent("photo.jpg").path])
        #expect(refreshed.assets.count == 1)
        for try await streamed in service.loadWorkspaceSnapshots() {
            #expect(streamed.assets.allSatisfy { $0.finderTags.isEmpty })
        }
    }
    @Test
    func recursivelyIndexesSupportedAssetsAndBuildsCompareGroups() async throws {
        let rootA = try temporaryDirectory(named: "library-a")
        let rootB = try temporaryDirectory(named: "library-b")

        try createFile(named: "set-a/look-001.CR2", under: rootA)
        try createFile(named: "set-a/look-002.heic", under: rootA)
        try createFile(named: "exports/banner.webp", under: rootA)
        try createFile(named: ".DS_Store", under: rootA)
        try createFile(named: "notes.txt", under: rootA)

        try createFile(named: "set-a/look-001.CR2", under: rootB)
        try createFile(named: "set-b/look-003.JPG", under: rootB)

        let service = FileSystemIndexingService(rootPaths: [rootA.path(), rootB.path()])

        let snapshot = try await service.loadWorkspace()

        #expect(snapshot.libraries.count == 2)
        #expect(snapshot.assets.count == 5)
        #expect(snapshot.assets.map(\.relativePath).sorted() == [
            "exports/banner.webp",
            "set-a/look-001.CR2",
            "set-a/look-001.CR2",
            "set-a/look-002.heic",
            "set-b/look-003.JPG",
        ])

        #expect(snapshot.assets.first(where: { $0.relativePath == "exports/banner.webp" })?.format == .webp)
        #expect(snapshot.assets.first(where: { $0.relativePath == "set-a/look-002.heic" })?.format == .heic)
        #expect(snapshot.compareGroups.count == 4)
        #expect(snapshot.compareGroups.first(where: { $0.relativePath == "set-a/look-001" })?.slots.count == 2)
        #expect(snapshot.keepFolderPath.hasSuffix("Keep"))
        #expect(snapshot.rejectFolderPath.hasSuffix("Reject"))
    }

    @Test
    func buildsCompareGroupsFromMatchingNamesWithDifferentExtensions() async throws {
        let rootA = try temporaryDirectory(named: "library-a")
        let rootB = try temporaryDirectory(named: "library-b")

        try createFile(named: "set-a/look-001.CR2", under: rootA)
        try createFile(named: "set-a/look-001.jpg", under: rootB)

        let service = FileSystemIndexingService(rootPaths: [rootA.path(), rootB.path()])

        let snapshot = try await service.loadWorkspace()
        let group = try #require(snapshot.compareGroups.first { $0.relativePath == "set-a/look-001" })

        #expect(group.slots.compactMap(\.asset).map(\.filename) == ["look-001.CR2", "look-001.jpg"])
    }

    @Test
    func streamsWorkspaceSnapshotsInAssetBatches() async throws {
        let root = try temporaryDirectory(named: "streaming-library")
        try createFile(named: "set-a/001.jpg", under: root)
        try createFile(named: "set-a/002.jpg", under: root)
        try createFile(named: "set-a/003.jpg", under: root)
        try createFile(named: "notes.txt", under: root)

        let service = FileSystemIndexingService(rootPaths: [root.path], assetBatchSize: 2)

        var assetCounts: [Int] = []
        for try await snapshot in service.loadWorkspaceSnapshots() {
            assetCounts.append(snapshot.assets.count)
        }

        #expect(assetCounts.last == 3)
        #expect(assetCounts == assetCounts.sorted())
        #expect(Set(assetCounts).isSubset(of: [0, 2, 3]))
    }

    @Test
    func coalescesLargeStreamingSnapshotsButAlwaysPublishesTheFinalAssetSet() async throws {
        let root = try temporaryDirectory(named: "coalesced-streaming-library")
        for index in 1...5 {
            try createFile(named: "set-a/\(String(format: "%03d", index)).jpg", under: root)
        }

        let service = FileSystemIndexingService(
            rootPaths: [root.path],
            assetBatchSize: 2,
            snapshotYieldInterval: 4
        )

        var assetCounts: [Int] = []
        for try await snapshot in service.loadWorkspaceSnapshots() {
            assetCounts.append(snapshot.assets.count)
        }

        // Slow consumers may skip superseded cumulative snapshots, never the final one.
        #expect(assetCounts.last == 5)
        #expect(assetCounts == assetCounts.sorted())
        #expect(Set(assetCounts).isSubset(of: [0, 4, 5]))
    }

    @Test
    func indexesSupportedAssetsInsideUnicodeRootPath() async throws {
        let unicodeRoot = try temporaryDirectory(named: "腿毛测试集")
        try createFile(named: "结果图/sample-001.png", under: unicodeRoot)
        try createFile(named: "结果图/sample-002.JPG", under: unicodeRoot)

        let service = FileSystemIndexingService(rootPaths: [unicodeRoot.path])

        let snapshot = try await service.loadWorkspace()

        #expect(snapshot.libraries.count == 1)
        #expect(snapshot.assets.map(\.relativePath).sorted() == [
            "结果图/sample-001.png",
            "结果图/sample-002.JPG",
        ])
    }

    @Test
    func returnsEmptyWorkspaceWhenRootFolderDoesNotExist() async throws {
        let missingRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let service = FileSystemIndexingService(rootPaths: [missingRoot.path])

        let snapshot = try await service.loadWorkspace()

        #expect(snapshot.libraries.isEmpty)
        #expect(snapshot.assets.isEmpty)
        #expect(snapshot.compareGroups.isEmpty)
    }
}

private struct ForbiddenFinderMetadataService: FinderTagSyncing {
    func readTags(at url: URL) throws -> [FinderTag] {
        Issue.record("P-only indexing must not read Finder tags")
        return []
    }
    func writeTags(_ tags: [FinderTag], at url: URL) throws {
        Issue.record("P-only indexing must not write Finder tags")
    }
}

private func temporaryDirectory(named name: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("PhotoTriageMacTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString + "-" + name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func createFile(named relativePath: String, under root: URL) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("test".utf8).write(to: url)
}
