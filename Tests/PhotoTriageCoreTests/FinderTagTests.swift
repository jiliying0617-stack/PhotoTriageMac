import Foundation
import PhotoTriageCore
import Testing

struct FinderTagTests {
    @Test
    func encodedFinderNamesPreserveNamesAndColors() {
        let tag = FinderTag(encodedName: "精选\n6")

        #expect(tag.name == "精选")
        #expect(tag.color == .red)
        #expect(tag.encodedName == "精选\n6")
        #expect(FinderTag(encodedName: "无色").color == .none)
    }

    @Test
    func normalizationDeduplicatesNamesCaseInsensitivelyAndKeepsLatestColor() {
        let tags = FinderTag.normalized([
            FinderTag(name: "Client", color: .blue),
            FinderTag(name: "client", color: .red),
            FinderTag(name: "交付", color: .green),
        ])

        #expect(tags.count == 2)
        #expect(tags[0] == FinderTag(name: "client", color: .red))
        #expect(tags[1] == FinderTag(name: "交付", color: .green))
    }

    @Test
    func colorSummaryCountsEachAssetOnlyOncePerColor() {
        let libraryID = UUID()
        let assets = [
            AssetRecord(
                libraryID: libraryID,
                filename: "one.jpg",
                relativePath: "one.jpg",
                format: .jpg,
                fileSizeBytes: 1,
                width: 1,
                height: 1,
                finderTags: [
                    FinderTag(name: "精选", color: .red),
                    FinderTag(name: "交付", color: .red),
                    FinderTag(name: "客户", color: .blue),
                ]
            ),
            AssetRecord(
                libraryID: libraryID,
                filename: "two.jpg",
                relativePath: "two.jpg",
                format: .jpg,
                fileSizeBytes: 1,
                width: 1,
                height: 1,
                finderTags: [FinderTag(name: "精选", color: .red)]
            ),
        ]

        let summary = FinderTagColorSummary(assets: assets)

        #expect(summary.count(for: .red) == 2)
        #expect(summary.count(for: .blue) == 1)
        #expect(summary.count(for: .green) == 0)
    }
}

struct FileSystemFinderTagServiceTests {
    @Test
    func writesReadsAndClearsColoredTagsOnUnicodeFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTriageFinderTags-\(UUID().uuidString)-中文", isDirectory: true)
        let fileURL = root.appendingPathComponent("样片.jpg")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("image-placeholder".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = FileSystemFinderTagService()
        let expected = [
            FinderTag(name: "精选", color: .red),
            FinderTag(name: "客户确认", color: .blue),
        ]

        try service.writeTags(expected, at: fileURL)
        #expect(try service.readTags(at: fileURL) == expected)

        try service.writeTags([], at: fileURL)
        #expect(try service.readTags(at: fileURL).isEmpty)
    }

    @Test
    func indexerReadsFinderTagsFromExistingFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTriageFinderIndex-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("tagged.jpg")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("image-placeholder".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let tagService = FileSystemFinderTagService()
        let expected = [FinderTag(name: "待交付", color: .orange)]
        try tagService.writeTags(expected, at: fileURL)

        let snapshot = try await FileSystemIndexingService(rootPaths: [root.path]).loadWorkspace()

        #expect(snapshot.assets.count == 1)
        #expect(snapshot.assets.first?.finderTags == expected)
    }
}

@MainActor
struct AppStateFinderTagTests {
    @Test
    func mixedSelectionToggleAddsTagToEverySelectedFileThenRemovesIt() async {
        let snapshot = makeFinderTagSnapshot(
            firstTags: [FinderTag(name: "精选", color: .red)],
            secondTags: []
        )
        let service = RecordingFinderTagService(snapshot: snapshot)
        let state = AppState(
            indexingService: FinderTagStaticIndexingService(snapshot: snapshot),
            finderTagService: service
        )
        await state.reloadWorkspace()
        let ids = state.assets.map(\.id)
        let tag = FinderTag(name: "精选", color: .red)

        #expect(state.finderTagSelectionState(tag, for: ids) == .mixed)
        await state.toggleFinderTag(tag, for: ids)
        #expect(state.finderTagSelectionState(tag, for: ids) == .all)
        #expect(state.assets.allSatisfy { $0.finderTags == [tag] })

        await state.toggleFinderTag(tag, for: ids)
        #expect(state.finderTagSelectionState(tag, for: ids) == .none)
        #expect(state.assets.allSatisfy { $0.finderTags.isEmpty })
        #expect(service.writeCount == 3)
    }

    @Test
    func writeFailureLeavesPublishedAssetTagsUnchanged() async {
        let original = [FinderTag(name: "原标签", color: .green)]
        let snapshot = makeFinderTagSnapshot(firstTags: original, secondTags: [])
        let service = RecordingFinderTagService(snapshot: snapshot)
        service.shouldFailWrites = true
        let state = AppState(
            indexingService: FinderTagStaticIndexingService(snapshot: snapshot),
            finderTagService: service
        )
        await state.reloadWorkspace()
        let firstID = state.assets[0].id

        await state.applyFinderTag(FinderTag(name: "新标签", color: .purple), for: [firstID])

        #expect(state.assets[0].finderTags == original)
        #expect(state.finderTagErrorMessage != nil)
    }

    @Test
    func externalRefreshReadsFinderChangesWithoutReloadingWorkspace() async {
        let snapshot = makeFinderTagSnapshot(firstTags: [], secondTags: [])
        let service = RecordingFinderTagService(snapshot: snapshot)
        let state = AppState(
            indexingService: FinderTagStaticIndexingService(snapshot: snapshot),
            finderTagService: service
        )
        await state.reloadWorkspace()
        let first = state.assets[0]
        let externalTag = FinderTag(name: "Finder 外部修改", color: .orange)
        service.tagsByPath[assetURL(first, in: snapshot).path] = [externalTag]

        await state.refreshFinderTagsFromDisk()

        #expect(state.assets[0].finderTags == [externalTag])
    }

    @Test
    func clearingTriageTagsDoesNotRemoveFinderTags() async {
        let finderTag = FinderTag(name: "客户标签", color: .blue)
        var snapshot = makeFinderTagSnapshot(firstTags: [finderTag], secondTags: [])
        snapshot.assets[0].ratingState = .keep
        snapshot.assets[0].appTags = [PriorityTag.p0.appTag]
        let service = RecordingFinderTagService(snapshot: snapshot)
        let state = AppState(
            indexingService: FinderTagStaticIndexingService(snapshot: snapshot),
            finderTagService: service
        )
        await state.reloadWorkspace()

        state.clearAllTriageTags(from: [state.assets[0].id])

        #expect(state.assets[0].ratingState == .pending)
        #expect(state.assets[0].priorityTag == nil)
        #expect(state.assets[0].finderTags == [finderTag])
        #expect(service.writeCount == 0)
    }

    @Test
    func compareGroupShortcutReplacesColorsAndRepeatingTheSameColorClearsEveryAsset() async {
        let snapshot = makeFinderTagSnapshot(
            firstTags: [FinderTag(name: "红色", color: .red), FinderTag(name: "旧标签", color: .green)],
            secondTags: [FinderTag(name: "黄色", color: .yellow)]
        )
        let service = RecordingFinderTagService(snapshot: snapshot)
        let state = AppState(
            indexingService: FinderTagStaticIndexingService(snapshot: snapshot),
            finderTagService: service
        )
        await state.reloadWorkspace()
        let ids = state.assets.map(\.id)
        state.setSelection(assetIDs: Set(ids))
        state.enterCompareMode()

        let tag = FinderTag(name: "橙色", color: .orange)
        await state.toggleExclusiveFinderTagForCompareGroup(tag)

        #expect(state.compareSelectionIDs.count == 2)
        #expect(state.assets.allSatisfy { $0.finderTags == [tag] })
        #expect(service.writeCount == 2)

        await state.toggleExclusiveFinderTagForCompareGroup(tag)

        #expect(state.assets.allSatisfy { $0.finderTags.isEmpty })
        #expect(service.writeCount == 4)

        await state.toggleExclusiveFinderTagForCompareGroup(tag)

        #expect(state.assets.allSatisfy { $0.finderTags == [tag] })
        #expect(service.writeCount == 6)
    }

    @Test
    func finderTagMutationPreservesCompareOrderAndFocusedAsset() async {
        let snapshot = makeFinderTagSnapshot(firstTags: [], secondTags: [])
        let service = RecordingFinderTagService(snapshot: snapshot)
        let state = AppState(
            indexingService: FinderTagStaticIndexingService(snapshot: snapshot),
            finderTagService: service
        )

        await state.reloadWorkspace()
        state.setSelection(assetIDs: Set(snapshot.assets.map(\.id)))
        state.enterCompareMode()
        state.focusCompareAsset(snapshot.assets[1].id)
        let originalOrder = state.compareSelectionIDs

        await state.toggleExclusiveFinderTag(
            FinderTag(name: "红色", color: .red),
            for: [snapshot.assets[1].id]
        )

        #expect(state.compareSelectionIDs == originalOrder)
        #expect(state.compareFocusedAsset?.id == snapshot.assets[1].id)
    }
}

private struct FinderTagStaticIndexingService: IndexingService {
    let snapshot: WorkspaceSnapshot

    func loadWorkspace() async throws -> WorkspaceSnapshot { snapshot }
}

private final class RecordingFinderTagService: FinderTagSyncing, @unchecked Sendable {
    var tagsByPath: [String: [FinderTag]]
    var shouldFailWrites = false
    private(set) var writeCount = 0
    private let lock = NSLock()

    init(snapshot: WorkspaceSnapshot) {
        tagsByPath = Dictionary(uniqueKeysWithValues: snapshot.assets.map { asset in
            (assetURL(asset, in: snapshot).path, asset.finderTags)
        })
    }

    func readTags(at url: URL) throws -> [FinderTag] {
        lock.withLock { tagsByPath[url.path] ?? [] }
    }

    func writeTags(_ tags: [FinderTag], at url: URL) throws {
        try lock.withLock {
            if shouldFailWrites { throw FinderTagTestError.writeFailed }
            tagsByPath[url.path] = tags
            writeCount += 1
        }
    }
}

private enum FinderTagTestError: Error {
    case writeFailed
}

private func makeFinderTagSnapshot(
    firstTags: [FinderTag],
    secondTags: [FinderTag]
) -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "FinderTags", path: "/tmp/finder-tags", columnIndex: 0)
    let assets = [
        AssetRecord(
            libraryID: library.id,
            filename: "first.jpg",
            relativePath: "first.jpg",
            format: .jpg,
            fileSizeBytes: 1,
            width: 1,
            height: 1,
            finderTags: firstTags
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "second.jpg",
            relativePath: "second.jpg",
            format: .jpg,
            fileSizeBytes: 1,
            width: 1,
            height: 1,
            finderTags: secondTags
        ),
    ]
    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private func assetURL(_ asset: AssetRecord, in snapshot: WorkspaceSnapshot) -> URL {
    let path = snapshot.libraries.first { $0.id == asset.libraryID }?.path ?? ""
    return URL(fileURLWithPath: path).appendingPathComponent(asset.relativePath)
}
