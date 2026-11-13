import Foundation
import PhotoTriageCore
import Testing

struct FileSystemExportServiceTests {
    @Test
    func exportsKeepAndRejectAssetsToConfiguredFoldersWhilePreservingRelativePaths() async throws {
        let sourceRoot = try exportTemporaryDirectory(named: "source")
        let keepRoot = try exportTemporaryDirectory(named: "keep")
        let rejectRoot = try exportTemporaryDirectory(named: "reject")
        let pendingRoot = try exportTemporaryDirectory(named: "pending")

        try exportCreateFile(named: "set-a/keep-001.CR2", under: sourceRoot, contents: "keep")
        try exportCreateFile(named: "set-b/reject-001.jpg", under: sourceRoot, contents: "reject")
        try exportCreateFile(named: "set-c/pending-001.heic", under: sourceRoot, contents: "pending")

        let library = LibraryFolder(displayName: "Originals", path: sourceRoot.path(), columnIndex: 0)
        let assets = [
            AssetRecord(
                libraryID: library.id,
                filename: "keep-001.CR2",
                relativePath: "set-a/keep-001.CR2",
                format: .cr2,
                fileSizeBytes: 4,
                width: 1,
                height: 1,
                ratingState: .keep,
            ),
            AssetRecord(
                libraryID: library.id,
                filename: "reject-001.jpg",
                relativePath: "set-b/reject-001.jpg",
                format: .jpg,
                fileSizeBytes: 6,
                width: 1,
                height: 1,
                ratingState: .reject,
            ),
            AssetRecord(
                libraryID: library.id,
                filename: "pending-001.heic",
                relativePath: "set-c/pending-001.heic",
                format: .heic,
                fileSizeBytes: 7,
                width: 1,
                height: 1,
                ratingState: .pending,
            ),
        ]

        let executor = FileSystemExportService()
        let request = ExportRequest(
            libraries: [library],
                assets: assets,
                keepFolderPath: keepRoot.path(),
                rejectFolderPath: rejectRoot.path(),
                pendingFolderPath: pendingRoot.path,
                includePending: false,
            )

        let summary = try await executor.export(request)

        let keptURL = keepRoot.appendingPathComponent("set-a/keep-001.CR2")
        let rejectedURL = rejectRoot.appendingPathComponent("set-b/reject-001.jpg")
        let pendingURL = pendingRoot.appendingPathComponent("set-c/pending-001.heic")

        #expect(FileManager.default.fileExists(atPath: keptURL.path()))
        #expect(FileManager.default.fileExists(atPath: rejectedURL.path()))
        #expect(!FileManager.default.fileExists(atPath: pendingURL.path()))
        #expect(try String(contentsOf: keptURL) == "keep")
        #expect(try String(contentsOf: rejectedURL) == "reject")
        #expect(summary.exportedCount == 2)
        #expect(summary.keepCount == 1)
        #expect(summary.rejectCount == 1)
        #expect(summary.pendingCount == 0)
    }

    @Test
    func exportsPendingAssetsToPendingFolderWhenIncluded() async throws {
        let sourceRoot = try exportTemporaryDirectory(named: "source-pending")
        let keepRoot = try exportTemporaryDirectory(named: "keep-pending")
        let rejectRoot = try exportTemporaryDirectory(named: "reject-pending")
        let pendingRoot = try exportTemporaryDirectory(named: "未处理")

        try exportCreateFile(named: "set-c/pending-001.heic", under: sourceRoot, contents: "pending")

        let library = LibraryFolder(displayName: "Originals", path: sourceRoot.path(), columnIndex: 0)
        let assets = [
            AssetRecord(
                libraryID: library.id,
                filename: "pending-001.heic",
                relativePath: "set-c/pending-001.heic",
                format: .heic,
                fileSizeBytes: 7,
                width: 1,
                height: 1,
                ratingState: .pending,
            )
        ]

        let summary = try await FileSystemExportService().export(
            ExportRequest(
                libraries: [library],
                assets: assets,
                keepFolderPath: keepRoot.path(),
                rejectFolderPath: rejectRoot.path(),
                pendingFolderPath: pendingRoot.path,
                includePending: true
            )
        )

        let pendingURL = pendingRoot.appendingPathComponent("set-c/pending-001.heic")

        #expect(FileManager.default.fileExists(atPath: pendingURL.path))
        #expect(try String(contentsOf: pendingURL) == "pending")
        #expect(summary.exportedCount == 1)
        #expect(summary.keepCount == 0)
        #expect(summary.rejectCount == 0)
        #expect(summary.pendingCount == 1)
    }

    @Test
    func exportsPriorityTaggedAssetsToPriorityFolders() async throws {
        let sourceRoot = try exportTemporaryDirectory(named: "source-priority")
        let keepRoot = try exportTemporaryDirectory(named: "keep-priority")
        let rejectRoot = try exportTemporaryDirectory(named: "reject-priority")
        let p0Root = try exportTemporaryDirectory(named: "P0")
        let p2Root = try exportTemporaryDirectory(named: "P2")

        try exportCreateFile(named: "set-a/p0.jpg", under: sourceRoot, contents: "p0")
        try exportCreateFile(named: "set-b/p2.jpg", under: sourceRoot, contents: "p2")
        try exportCreateFile(named: "set-c/untagged.jpg", under: sourceRoot, contents: "untagged")

        let library = LibraryFolder(displayName: "Originals", path: sourceRoot.path(), columnIndex: 0)
        let assets = [
            AssetRecord(
                libraryID: library.id,
                filename: "p0.jpg",
                relativePath: "set-a/p0.jpg",
                format: .jpg,
                fileSizeBytes: 2,
                width: 1,
                height: 1,
                appTags: [PriorityTag.p0.appTag]
            ),
            AssetRecord(
                libraryID: library.id,
                filename: "p2.jpg",
                relativePath: "set-b/p2.jpg",
                format: .jpg,
                fileSizeBytes: 2,
                width: 1,
                height: 1,
                appTags: [PriorityTag.p2.appTag]
            ),
            AssetRecord(
                libraryID: library.id,
                filename: "untagged.jpg",
                relativePath: "set-c/untagged.jpg",
                format: .jpg,
                fileSizeBytes: 8,
                width: 1,
                height: 1
            ),
        ]

        let summary = try await FileSystemExportService().export(
            ExportRequest(
                libraries: [library],
                assets: assets,
                keepFolderPath: keepRoot.path,
                rejectFolderPath: rejectRoot.path,
                priorityTagFolderPaths: [
                    .p0: p0Root.path,
                    .p2: p2Root.path,
                ],
                includePending: false,
                includedPriorityTags: [.p0, .p2]
            )
        )

        #expect(FileManager.default.fileExists(atPath: p0Root.appendingPathComponent("set-a/p0.jpg").path))
        #expect(FileManager.default.fileExists(atPath: p2Root.appendingPathComponent("set-b/p2.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: p0Root.appendingPathComponent("set-c/untagged.jpg").path))
        #expect(summary.exportedCount == 2)
        #expect(summary.priorityTagSummary.p0Count == 1)
        #expect(summary.priorityTagSummary.p1Count == 0)
        #expect(summary.priorityTagSummary.p2Count == 1)
    }

    @Test
    func exportsAssetsWhoseSourceAndDestinationRootsContainUnicodeCharacters() async throws {
        let sourceRoot = try exportTemporaryDirectory(named: "原图")
        let keepRoot = try exportTemporaryDirectory(named: "保留")
        let rejectRoot = try exportTemporaryDirectory(named: "淘汰")

        try exportCreateFile(named: "结果图/样张-001.png", under: sourceRoot, contents: "keep")

        let library = LibraryFolder(displayName: "原图", path: sourceRoot.path, columnIndex: 0)
        let assets = [
            AssetRecord(
                libraryID: library.id,
                filename: "样张-001.png",
                relativePath: "结果图/样张-001.png",
                format: .png,
                fileSizeBytes: 4,
                width: 1,
                height: 1,
                ratingState: .keep,
            )
        ]

        let executor = FileSystemExportService()
        let request = ExportRequest(
            libraries: [library],
            assets: assets,
            keepFolderPath: keepRoot.path,
            rejectFolderPath: rejectRoot.path,
            includePending: false,
        )

        let summary = try await executor.export(request)
        let keptURL = keepRoot.appendingPathComponent("结果图/样张-001.png")

        #expect(FileManager.default.fileExists(atPath: keptURL.path))
        #expect(try String(contentsOf: keptURL) == "keep")
        #expect(summary.exportedCount == 1)
        #expect(summary.keepCount == 1)
        #expect(summary.rejectCount == 0)
    }

    @Test
    func exportRenamesConflictingDestinationInsteadOfOverwriting() async throws {
        let sourceRoot = try exportTemporaryDirectory(named: "source-conflict")
        let keepRoot = try exportTemporaryDirectory(named: "keep-conflict")
        let rejectRoot = try exportTemporaryDirectory(named: "reject-conflict")

        try exportCreateFile(named: "set-a/keep-001.jpg", under: sourceRoot, contents: "new")
        try exportCreateFile(named: "set-a/keep-001.jpg", under: keepRoot, contents: "existing")

        let library = LibraryFolder(displayName: "Originals", path: sourceRoot.path, columnIndex: 0)
        let assets = [
            AssetRecord(
                libraryID: library.id,
                filename: "keep-001.jpg",
                relativePath: "set-a/keep-001.jpg",
                format: .jpg,
                fileSizeBytes: 3,
                width: 1,
                height: 1,
                ratingState: .keep
            )
        ]

        let summary = try await FileSystemExportService().export(
            ExportRequest(
                libraries: [library],
                assets: assets,
                keepFolderPath: keepRoot.path,
                rejectFolderPath: rejectRoot.path,
                includePending: false
            )
        )

        let originalURL = keepRoot.appendingPathComponent("set-a/keep-001.jpg")
        let renamedURL = keepRoot.appendingPathComponent("set-a/keep-001 2.jpg")
        #expect(try String(contentsOf: originalURL) == "existing")
        #expect(try String(contentsOf: renamedURL) == "new")
        #expect(summary.renamedConflictCount == 1)
    }

    @Test
    func exportConflictLookupHandlesManyExistingRenames() async throws {
        let sourceRoot = try exportTemporaryDirectory(named: "source-many-conflicts")
        let keepRoot = try exportTemporaryDirectory(named: "keep-many-conflicts")
        let rejectRoot = try exportTemporaryDirectory(named: "reject-many-conflicts")

        try exportCreateFile(named: "set-a/keep-001.jpg", under: sourceRoot, contents: "new")
        try exportCreateFile(named: "set-a/keep-001.jpg", under: keepRoot, contents: "existing")
        for index in 2...250 {
            try exportCreateFile(named: "set-a/keep-001 \(index).jpg", under: keepRoot, contents: "existing \(index)")
        }

        let library = LibraryFolder(displayName: "Originals", path: sourceRoot.path, columnIndex: 0)
        let asset = AssetRecord(
            libraryID: library.id,
            filename: "keep-001.jpg",
            relativePath: "set-a/keep-001.jpg",
            format: .jpg,
            fileSizeBytes: 3,
            width: 1,
            height: 1,
            ratingState: .keep
        )

        let summary = try await FileSystemExportService().export(
            ExportRequest(
                libraries: [library],
                assets: [asset],
                keepFolderPath: keepRoot.path,
                rejectFolderPath: rejectRoot.path,
                includePending: false
            )
        )

        let renamedURL = keepRoot.appendingPathComponent("set-a/keep-001 251.jpg")
        #expect(try String(contentsOf: renamedURL) == "new")
        #expect(summary.renamedConflictCount == 1)
    }

    @Test
    func exportsFinderColorTaggedAssetsToSelectedColorFolders() async throws {
        let sourceRoot = try exportTemporaryDirectory(named: "source-finder-colors")
        let keepRoot = try exportTemporaryDirectory(named: "keep-finder-colors")
        let rejectRoot = try exportTemporaryDirectory(named: "reject-finder-colors")
        let redRoot = try exportTemporaryDirectory(named: "Finder标签-红色")
        let blueRoot = try exportTemporaryDirectory(named: "Finder标签-蓝色")

        try exportCreateFile(named: "set-a/red.jpg", under: sourceRoot, contents: "red")
        try exportCreateFile(named: "set-b/blue.jpg", under: sourceRoot, contents: "blue")
        let library = LibraryFolder(displayName: "Originals", path: sourceRoot.path, columnIndex: 0)
        let assets = [
            AssetRecord(
                libraryID: library.id,
                filename: "red.jpg",
                relativePath: "set-a/red.jpg",
                format: .jpg,
                fileSizeBytes: 3,
                width: 1,
                height: 1,
                finderTags: [FinderTag(name: "精选", color: .red)]
            ),
            AssetRecord(
                libraryID: library.id,
                filename: "blue.jpg",
                relativePath: "set-b/blue.jpg",
                format: .jpg,
                fileSizeBytes: 4,
                width: 1,
                height: 1,
                finderTags: [FinderTag(name: "客户", color: .blue)]
            ),
        ]

        let summary = try await FileSystemExportService().export(
            ExportRequest(
                libraries: [library],
                assets: assets,
                keepFolderPath: keepRoot.path,
                rejectFolderPath: rejectRoot.path,
                finderTagFolderPaths: [.red: redRoot.path, .blue: blueRoot.path],
                includeKeep: false,
                includeReject: false,
                includePending: false,
                includedFinderTagColors: [.red]
            )
        )

        #expect(FileManager.default.fileExists(atPath: redRoot.appendingPathComponent("set-a/red.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: blueRoot.appendingPathComponent("set-b/blue.jpg").path))
        #expect(summary.exportedCount == 1)
        #expect(summary.finderTagColorSummary.count(for: .red) == 1)
        #expect(summary.finderTagColorSummary.count(for: .blue) == 0)
    }

    @Test
    func pOnlyExportIgnoresLegacyPendingTagsAndDoesNotSyncExistingCopies() async throws {
        let fixture = try PendingTagExportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let tags = FileSystemFinderTagService()
        let original = [FinderTag(name: "已有标签", color: .green)]
        try tags.writeTags(original, at: fixture.sourceURL)
        var asset = fixture.asset
        asset.finderTags = [FinderTag(name: "旧版待同步", color: .red)]
        asset.finderTagSyncIssue = "不再同步"
        var request = fixture.request(for: asset)
        let obsoleteColorFolder = fixture.root.appendingPathComponent("obsolete-color")
        request.includedFinderTagColors = [.red]
        request.finderTagFolderPaths = [.red: obsoleteColorFolder.path]
        let exporter = FileSystemExportService(synchronizesFinderTags: false)
        let first = try await exporter.export(request)
        #expect(first.exportedCount == 1)
        #expect(first.failures.isEmpty)
        #expect(try tags.readTags(at: fixture.outputURL) == original)
        #expect(!FileManager.default.fileExists(atPath: obsoleteColorFolder.path))
        let destinationTags = [FinderTag(name: "用户在导出副本上打的标签", color: .blue)]
        try tags.writeTags(destinationTags, at: fixture.outputURL)
        let second = try await exporter.export(request)
        #expect(second.skippedCount == 1)
        #expect(second.failures.isEmpty)
        #expect(try tags.readTags(at: fixture.outputURL) == destinationTags)
        #expect(try tags.readTags(at: fixture.sourceURL) == original)
    }

    @Test
    func exportsPendingFinderTagsAndUpdatesAnExistingCopyIncludingClearingTags() async throws {
        let fixture = try PendingTagExportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = FileSystemFinderTagService()
        let sourceTags = [FinderTag(name: "原图标签", color: .green)]
        try service.writeTags(sourceTags, at: fixture.sourceURL)
        var asset = fixture.asset
        asset.finderTags = [FinderTag(name: "本地红色", color: .red)]
        asset.finderTagSyncIssue = "源文件只读"

        let first = try await FileSystemExportService().export(fixture.request(for: asset))

        #expect(first.exportedCount == 1)
        #expect(first.failures.isEmpty)
        #expect(try service.readTags(at: fixture.outputURL) == asset.finderTags)
        #expect(try service.readTags(at: fixture.sourceURL) == sourceTags)
        #expect(try Data(contentsOf: fixture.outputURL) == Data(contentsOf: fixture.sourceURL))

        asset.finderTags = [FinderTag(name: "本地蓝色", color: .blue)]
        let second = try await FileSystemExportService().export(fixture.request(for: asset))
        #expect(second.exportedCount == 0)
        #expect(second.skippedCount == 1)
        #expect(second.failures.isEmpty)
        #expect(try service.readTags(at: fixture.outputURL) == asset.finderTags)

        asset.finderTags = []
        let cleared = try await FileSystemExportService().export(fixture.request(for: asset))
        #expect(cleared.exportedCount == 0)
        #expect(cleared.skippedCount == 1)
        #expect(cleared.failures.isEmpty)
        #expect(try service.readTags(at: fixture.outputURL).isEmpty)
        #expect(try service.readTags(at: fixture.sourceURL) == sourceTags)
        #expect(try String(contentsOf: fixture.sourceURL, encoding: .utf8) == "photo-content")
    }

    @Test
    func normalExportStillPreservesAndRefreshesSourceFinderTags() async throws {
        let fixture = try PendingTagExportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = FileSystemFinderTagService()
        let original = [FinderTag(name: "Finder原标签", color: .green)]
        let changed = [FinderTag(name: "Finder更新标签", color: .orange)]
        try service.writeTags(original, at: fixture.sourceURL)
        var asset = fixture.asset
        asset.finderTags = [FinderTag(name: "过期缓存", color: .red)]

        let first = try await FileSystemExportService().export(fixture.request(for: asset))
        #expect(first.exportedCount == 1)
        #expect(first.failures.isEmpty)
        #expect(try service.readTags(at: fixture.outputURL) == original)

        try service.writeTags(changed, at: fixture.sourceURL)
        let second = try await FileSystemExportService().export(fixture.request(for: asset))
        #expect(second.skippedCount == 1)
        #expect(second.failures.isEmpty)
        #expect(try service.readTags(at: fixture.outputURL) == changed)
    }

    @Test
    func locallySavedRedTagExportsToRedColorFolderWithoutChangingSource() async throws {
        let fixture = try PendingTagExportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var asset = fixture.asset
        asset.finderTags = [FinderTag(name: "红色", color: .red)]
        asset.finderTagSyncIssue = "网络盘拒绝写入"
        var request = fixture.request(for: asset)
        request.includeKeep = false
        request.includedFinderTagColors = [.red]
        request.finderTagFolderPaths = [.red: fixture.outputURL.deletingLastPathComponent().path]
        let summary = try await FileSystemExportService().export(request)
        #expect(summary.exportedCount == 1)
        #expect(summary.finderTagColorSummary.count(for: .red) == 1)
        #expect(summary.failures.isEmpty)
        #expect(try FileSystemFinderTagService().readTags(at: fixture.outputURL) == asset.finderTags)
        #expect(try FileSystemFinderTagService().readTags(at: fixture.sourceURL).isEmpty)
    }

    @Test
    func normalSymbolicLinkExportRemainsIdempotent() async throws {
        let fixture = try PendingTagExportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let link = fixture.sourceURL.deletingLastPathComponent().appendingPathComponent("linked.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.sourceURL)
        var asset = fixture.asset
        asset.filename = link.lastPathComponent
        asset.relativePath = link.lastPathComponent
        let first = try await FileSystemExportService().export(fixture.request(for: asset))
        let second = try await FileSystemExportService().export(fixture.request(for: asset))
        #expect(first.exportedCount == 1)
        #expect(first.failures.isEmpty)
        #expect(second.skippedCount == 1)
        #expect(second.exportedCount == 0)
        #expect(second.failures.isEmpty)
    }

    @Test
    func pendingFinderTagsCanBeExportedFromAReadOnlySource() async throws {
        let fixture = try PendingTagExportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = FileSystemFinderTagService()
        let original = [FinderTag(name: "原图标签", color: .green)]
        try service.writeTags(original, at: fixture.sourceURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: fixture.sourceURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fixture.sourceURL.path)
        }
        var asset = fixture.asset
        asset.finderTags = [FinderTag(name: "应用内标签", color: .red)]
        asset.finderTagSyncIssue = "源文件只读"

        let summary = try await FileSystemExportService().export(fixture.request(for: asset))

        #expect(summary.exportedCount == 1)
        #expect(summary.failures.isEmpty)
        #expect(try service.readTags(at: fixture.outputURL) == asset.finderTags)
        #expect(try service.readTags(at: fixture.sourceURL) == original)
        let sourceAttributes = try FileManager.default.attributesOfItem(atPath: fixture.sourceURL.path)
        #expect((sourceAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o444)
        let outputAttributes = try FileManager.default.attributesOfItem(atPath: fixture.outputURL.path)
        #expect((outputAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o444)

        asset.finderTags = []
        let cleared = try await FileSystemExportService().export(fixture.request(for: asset))
        #expect(cleared.skippedCount == 1)
        #expect(cleared.failures.isEmpty)
        #expect(try service.readTags(at: fixture.outputURL).isEmpty)
        #expect(try service.readTags(at: fixture.sourceURL) == original)
    }

    @Test
    func pendingFinderTagsExportedToTheSourceFolderCreateAnIndependentCopy() async throws {
        let fixture = try PendingTagExportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = FileSystemFinderTagService()
        let original = [FinderTag(name: "原图标签", color: .green)]
        try service.writeTags(original, at: fixture.sourceURL)
        var asset = fixture.asset
        asset.finderTags = [FinderTag(name: "应用内标签", color: .red)]
        asset.finderTagSyncIssue = "写入失败"
        var request = fixture.request(for: asset)
        request.keepFolderPath = fixture.sourceURL.deletingLastPathComponent().path

        let summary = try await FileSystemExportService().export(request)

        let copy = fixture.sourceURL.deletingLastPathComponent().appendingPathComponent("photo 2.jpg")
        #expect(summary.exportedCount == 1)
        #expect(summary.renamedConflictCount == 1)
        #expect(summary.failures.isEmpty)
        #expect(try service.readTags(at: copy) == asset.finderTags)
        #expect(try service.readTags(at: fixture.sourceURL) == original)
    }

    @Test(arguments: ["source-symbolic-link", "destination-symbolic-link", "destination-hard-link"])
    func pendingFinderTagExportNeverWritesTagsThroughLinksToTheSource(linkKind: String) async throws {
        let fixture = try PendingTagExportFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = FileSystemFinderTagService()
        let original = [FinderTag(name: "原图标签", color: .green)]
        try service.writeTags(original, at: fixture.sourceURL)
        var asset = fixture.asset
        asset.finderTags = [FinderTag(name: "应用内标签", color: .red)]
        asset.finderTagSyncIssue = "写入失败"
        var expectedOutput = fixture.outputURL
        switch linkKind {
        case "source-symbolic-link":
            let link = fixture.sourceURL.deletingLastPathComponent().appendingPathComponent("linked.jpg")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.sourceURL)
            asset.filename = link.lastPathComponent
            asset.relativePath = link.lastPathComponent
            expectedOutput = fixture.outputURL.deletingLastPathComponent().appendingPathComponent("linked.jpg")
        case "destination-symbolic-link":
            try FileManager.default.createSymbolicLink(at: fixture.outputURL, withDestinationURL: fixture.sourceURL)
            expectedOutput = fixture.outputURL.deletingLastPathComponent().appendingPathComponent("photo 2.jpg")
        default:
            try FileManager.default.linkItem(at: fixture.sourceURL, to: fixture.outputURL)
            expectedOutput = fixture.outputURL.deletingLastPathComponent().appendingPathComponent("photo 2.jpg")
        }

        let summary = try await FileSystemExportService().export(fixture.request(for: asset))

        #expect(summary.exportedCount == 1)
        #expect(summary.failures.isEmpty)
        #expect(try service.readTags(at: expectedOutput) == asset.finderTags)
        #expect(try service.readTags(at: fixture.sourceURL) == original)
        #expect(try expectedOutput.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
        #expect(try Data(contentsOf: expectedOutput) == Data(contentsOf: fixture.sourceURL))
    }
}

private struct PendingTagExportFixture {
    let root: URL
    let sourceURL: URL
    let outputURL: URL
    let library: LibraryFolder
    let asset: AssetRecord

    init() throws {
        root = try exportTemporaryDirectory(named: "pending-finder-tag")
        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let outputRoot = root.appendingPathComponent("output", isDirectory: true)
        try exportCreateFile(named: "photo.jpg", under: sourceRoot, contents: "photo-content")
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        sourceURL = sourceRoot.appendingPathComponent("photo.jpg")
        outputURL = outputRoot.appendingPathComponent("photo.jpg")
        library = LibraryFolder(displayName: "Originals", path: sourceRoot.path, columnIndex: 0)
        asset = AssetRecord(
            libraryID: library.id, filename: "photo.jpg", relativePath: "photo.jpg", format: .jpg,
            fileSizeBytes: 13, width: 1, height: 1, ratingState: .keep
        )
    }

    func request(for asset: AssetRecord) -> ExportRequest {
        ExportRequest(
            libraries: [library], assets: [asset],
            keepFolderPath: outputURL.deletingLastPathComponent().path,
            rejectFolderPath: root.appendingPathComponent("reject").path,
            includeReject: false, includePending: false
        )
    }
}

private func exportTemporaryDirectory(named name: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("PhotoTriageMacExportTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString + "-" + name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func exportCreateFile(named relativePath: String, under root: URL, contents: String) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: url)
}
