import Foundation
import PhotoTriageCore
import Testing

@MainActor
struct PriorityTagCatalogTests {
    @Test
    func keepsLegacyIdentityEncodingAndRecognizesNewTags() throws {
        #expect(try JSONDecoder().decode(PriorityTag.self, from: Data("\"P1\"".utf8)) == .p1)
        #expect(try JSONEncoder().encode(PriorityTag.p1) == Data("\"P1\"".utf8))
        #expect(PriorityTag.fromAppTag(AppTag(name: "p10")) == PriorityTag(index: 10))
        #expect(PriorityTag.fromAppTag(AppTag(name: "Portrait")) == nil)
        #expect(PriorityTag(rawValue: "P-1") == nil)
        #expect([PriorityTag(index: 10), .p2, PriorityTag(index: 3)].sorted().map(\.rawValue) == ["P2", "P3", "P10"])
    }

    @Test
    func renamePersistsWithoutLosingExistingImageTagsAndSupportsSearch() async throws {
        let suite = "PriorityTagCatalogTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPriorityTagCatalogStore(defaults: defaults)
        let fixture = catalogFixture()
        let state = AppState(indexingService: CatalogIndexingService(snapshot: fixture), priorityTagCatalogStore: store)
        await state.reloadWorkspace()
        let assetID = try #require(state.assets.first?.id)
        state.applyPriorityTag(.p1, to: [assetID])

        try state.renamePriorityTag(.p1, to: "  皮肤问题  ")
        #expect(state.priorityTagDisplayName(.p1) == "皮肤问题")
        #expect(state.assets.first?.priorityTag == .p1)
        #expect(state.assets.first?.appTags == [PriorityTag.p1.appTag])
        #expect(state.priorityTagSummary.p1Count == 1)
        state.selectCategoryFilter(.priority(.p1))
        #expect(state.activeFilterDescription.hasSuffix(" / 皮肤问题"))
        #expect(state.filteredAssets.count == 1)
        state.searchText = "皮肤"
        #expect(state.filteredAssets.count == 1)

        let restored = AppState(indexingService: CatalogIndexingService(snapshot: fixture), priorityTagCatalogStore: store)
        #expect(restored.priorityTagDisplayName(.p1) == "皮肤问题")
    }

    @Test
    func addedTagsContinueSequentiallyAndParticipateInAllSummaries() async throws {
        let state = AppState(indexingService: CatalogIndexingService(snapshot: catalogFixture()))
        await state.reloadWorkspace()
        let third = try state.addPriorityTag()
        let fourth = try state.addPriorityTag()
        #expect(third.rawValue == "P3")
        #expect(fourth.rawValue == "P4")
        try state.renamePriorityTag(third, to: "手部异常")
        let assetID = try #require(state.assets.first?.id)
        state.applyPriorityTag(third, to: [assetID])
        #expect(state.assets.first?.ratingState == .reject)
        #expect(state.priorityTagSummary.count(for: third) == 1)
        #expect(state.categorySummary.priorityTagSummary.count(for: third) == 1)
        #expect(state.exportScopeSummary.priorityTagSummary.count(for: third) == 1)
        #expect(state.priorityTagSummary.taggedCount == 1)
        state.selectCategoryFilter(.priority(third))
        #expect(state.filteredAssets.count == 1)

        state.applyPriorityTag(fourth, to: [assetID])
        #expect(state.assets.first?.appTags == [fourth.appTag])
        #expect(state.priorityTagSummary.count(for: third) == 0)
        #expect(state.priorityTagSummary.count(for: fourth) == 1)
        state.clearPriorityTags(from: [assetID])
        #expect(state.priorityTagSummary.taggedCount == 0)
    }

    @Test
    func rejectsNamesThatWouldMergeOrEscapeExportFolders() throws {
        let state = AppState(indexingService: CatalogIndexingService(snapshot: catalogFixture()))
        for invalid in ["", "  ", "../outside", "sub/folder", "folder:name", "folder\\name", "one\ntwo", ".hidden", "Keep", "未处理", "P3"] {
            #expect(throws: (any Error).self) { try state.renamePriorityTag(.p1, to: invalid) }
            #expect(state.priorityTagDisplayName(.p1) == "P1")
        }
        try state.renamePriorityTag(.p0, to: "皮肤问题")
        #expect(throws: PriorityTagCatalogError.duplicateName) {
            try state.renamePriorityTag(.p1, to: "皮肤问题")
        }
    }

    @Test
    func catalogRestoresNamesAndNextNumberAfterSessionCleanup() async throws {
        let suite = "PriorityTagPersistence.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPriorityTagCatalogStore(defaults: defaults)
        let state = AppState(indexingService: CatalogIndexingService(snapshot: catalogFixture()), priorityTagCatalogStore: store)
        await state.reloadWorkspace()
        for tag in PriorityTag.allCases { try state.renamePriorityTag(tag, to: "问题类型\(tag.index)") }
        for _ in 3...10 { try state.addPriorityTag() }
        try state.renamePriorityTag(PriorityTag(index: 10), to: "细节修复")
        state.clearSessionCaches()
        let restored = AppState(indexingService: CatalogIndexingService(snapshot: catalogFixture()), priorityTagCatalogStore: store)
        #expect(restored.priorityTags.map(\.index) == Array(0...10))
        #expect(restored.priorityTagDisplayName(.p0) == "问题类型0")
        #expect(restored.priorityTagDisplayName(.p2) == "问题类型2")
        #expect(restored.priorityTagDisplayName(PriorityTag(index: 10)) == "细节修复")
        #expect(try restored.addPriorityTag() == PriorityTag(index: 11))
    }

    @Test
    func failedPersistenceDoesNotPublishUnsavedNameOrNewLabel() throws {
        let state = AppState(indexingService: CatalogIndexingService(snapshot: catalogFixture()), priorityTagCatalogStore: FailingCatalogStore())
        #expect(throws: (any Error).self) { try state.renamePriorityTag(.p1, to: "手部异常") }
        #expect(throws: (any Error).self) { try state.addPriorityTag() }
        #expect(state.priorityTagDisplayName(.p1) == "P1")
        #expect(state.priorityTags == [.p0, .p1, .p2])
    }

    @Test
    func restoredCustomDecisionsRemainAccessibleWhenCatalogIsMissing() async throws {
        var fixture = catalogFixture()
        let tag = PriorityTag(index: 7)
        fixture.assets[0].appTags = [tag.appTag]
        let state = AppState(indexingService: CatalogIndexingService(snapshot: fixture))
        await state.reloadWorkspace()
        #expect(state.priorityTags.contains(tag))
        #expect(state.priorityTagSummary.count(for: tag) == 1)
        #expect(try state.addPriorityTag() == PriorityTag(index: 8))
    }

    @Test
    func newTagExportsIntoNamedCategoryWithoutRenamingOriginalFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("p-label-export-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceRoot = directory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let source = sourceRoot.appendingPathComponent("image.jpg")
        try Data("image".utf8).write(to: source)
        let tag = PriorityTag(index: 3)
        let library = LibraryFolder(displayName: "source", path: sourceRoot.path, columnIndex: 0)
        let asset = AssetRecord(libraryID: library.id, filename: "image.jpg", relativePath: "image.jpg", format: .jpg,
                                fileSizeBytes: 5, width: 1, height: 1, appTags: [tag.appTag])
        let destination = directory.appendingPathComponent("手部异常", isDirectory: true)
        let summary = try await FileSystemExportService().export(ExportRequest(
            libraries: [library], assets: [asset], keepFolderPath: directory.appendingPathComponent("Keep").path,
            rejectFolderPath: directory.appendingPathComponent("Reject").path,
            priorityTagFolderPaths: [tag: destination.path], includeKeep: false, includeReject: false,
            includePending: false, includedPriorityTags: [tag]
        ))
        #expect(summary.exportedCount == 1)
        #expect(summary.priorityTagSummary.count(for: tag) == 1)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("image.jpg").path))
        #expect(try Data(contentsOf: source) == Data("image".utf8))
    }
}

private func catalogFixture() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "Photos", path: "/test/photos", columnIndex: 0)
    let asset = AssetRecord(libraryID: library.id, filename: "image.jpg", relativePath: "image.jpg", format: .jpg,
                            fileSizeBytes: 100, width: 1, height: 1)
    return WorkspaceSnapshot(libraries: [library], assets: [asset], compareGroups: [],
                             keepFolderPath: "/exports/Keep", rejectFolderPath: "/exports/Reject")
}

private struct CatalogIndexingService: IndexingService {
    let snapshot: WorkspaceSnapshot
    func loadWorkspace() async throws -> WorkspaceSnapshot { snapshot }
}

private struct FailingCatalogStore: PriorityTagCatalogPersisting {
    func load() throws -> [PriorityTagDefinition] { PriorityTagDefinition.defaults }
    func save(_ definitions: [PriorityTagDefinition]) throws { throw CocoaError(.fileWriteNoPermission) }
}
