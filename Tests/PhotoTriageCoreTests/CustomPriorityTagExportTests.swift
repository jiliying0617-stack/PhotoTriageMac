import Foundation
import PhotoTriageCore
import Testing

struct CustomPriorityTagExportTests {
    @Test
    func exportFolderNamesFollowEditedLabelsAndIncludeNewLabels() {
        let root = URL(fileURLWithPath: "/exports/batch", isDirectory: true)
        let p3 = PriorityTag(index: 3)
        let paths = PriorityTagExportFolders.paths(under: root, definitions: [
            PriorityTagDefinition(tag: .p1, name: "手部问题"),
            PriorityTagDefinition(tag: p3, name: "光影问题"),
        ])

        #expect(paths[.p0] == "/exports/batch/P0")
        #expect(paths[.p1] == "/exports/batch/手部问题")
        #expect(paths[p3] == "/exports/batch/光影问题")
    }

    @Test
    func exportsNewPriorityLabelsIntoTheirNamedFoldersWithoutRenamingOriginals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("custom-p-export-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let destinationRoot = root.appendingPathComponent("export", isDirectory: true)
        let relativePath = "原图/样张.png"
        let source = sourceRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original image bytes".utf8).write(to: source)
        let library = LibraryFolder(displayName: "素材", path: sourceRoot.path, columnIndex: 0)
        let p3 = PriorityTag(index: 3)
        let p10 = PriorityTag(index: 10)
        let folderPaths = PriorityTagExportFolders.paths(under: destinationRoot, definitions: [
            PriorityTagDefinition(tag: p3, name: "手部问题"),
            PriorityTagDefinition(tag: p10, name: "光影问题"),
        ])
        let assets = [p3, p10].map { tag in
            AssetRecord(libraryID: library.id, filename: "样张.png", relativePath: relativePath,
                        format: .png, fileSizeBytes: 20, width: 1, height: 1,
                        appTags: [tag.appTag])
        }
        let summary = try await FileSystemExportService().export(ExportRequest(
            libraries: [library], assets: assets,
            keepFolderPath: destinationRoot.appendingPathComponent("保留").path,
            rejectFolderPath: destinationRoot.appendingPathComponent("淘汰").path,
            priorityTagFolderPaths: folderPaths,
            includeKeep: false, includeReject: false, includePending: false,
            includedPriorityTags: [p3, p10]
        ))

        #expect(summary.failures.isEmpty)
        #expect(summary.exportedCount == 2)
        #expect(summary.priorityTagSummary.count(for: p3) == 1)
        #expect(summary.priorityTagSummary.count(for: p10) == 1)
        #expect(summary.priorityTagSummary.taggedCount == 2)
        for name in ["手部问题", "光影问题"] {
            let exported = destinationRoot.appendingPathComponent(name).appendingPathComponent(relativePath)
            #expect(try Data(contentsOf: exported) == Data(contentsOf: source))
        }
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test
    func invalidPersistedLabelNamesCannotEscapeExportDirectory() {
        let root = URL(fileURLWithPath: "/exports/batch", isDirectory: true)
        let paths = PriorityTagExportFolders.paths(under: root, definitions: [
            PriorityTagDefinition(tag: .p1, name: "../outside"),
            PriorityTagDefinition(tag: PriorityTag(index: 3), name: "/tmp/outside"),
        ])

        #expect(paths[.p1] == "/exports/batch/P1")
        #expect(paths[PriorityTag(index: 3)] == nil)
        #expect(paths.values.allSatisfy { $0.hasPrefix("/exports/batch/") })
    }
}
