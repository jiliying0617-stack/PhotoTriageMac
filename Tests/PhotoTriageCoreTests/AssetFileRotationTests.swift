import AppKit
import Foundation
import PhotoTriageCore
import Testing

@MainActor
struct AssetFileRotationTests {
    @Test
    func rotatingLocalPNGUpdatesFileDimensionsAndPreservesFinderTags() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTriageRotation-\(UUID().uuidString)", isDirectory: true)
        let fileURL = root.appendingPathComponent("待旋转.png")
        let otherFileURL = root.appendingPathComponent("保持不变.png")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writePNG(width: 30, height: 20, to: fileURL)
        try writePNG(width: 40, height: 24, to: otherFileURL)

        let tag = FinderTag(name: "精选", color: .red)
        let finderTagService = FileSystemFinderTagService()
        try finderTagService.writeTags([tag], at: fileURL)
        let library = LibraryFolder(displayName: "Rotation", path: root.path, columnIndex: 0)
        let asset = AssetRecord(
            libraryID: library.id,
            filename: fileURL.lastPathComponent,
            relativePath: fileURL.lastPathComponent,
            format: .png,
            fileSizeBytes: 1,
            width: 30,
            height: 20,
            finderTags: [tag]
        )
        let otherAsset = AssetRecord(
            libraryID: library.id,
            filename: otherFileURL.lastPathComponent,
            relativePath: otherFileURL.lastPathComponent,
            format: .png,
            fileSizeBytes: 1,
            width: 40,
            height: 24
        )
        let snapshot = WorkspaceSnapshot(
            libraries: [library],
            assets: [asset, otherAsset],
            compareGroups: [],
            keepFolderPath: root.appendingPathComponent("Keep").path,
            rejectFolderPath: root.appendingPathComponent("Reject").path
        )
        let state = AppState(
            indexingService: RotationStaticIndexingService(snapshot: snapshot),
            finderTagService: finderTagService
        )
        await state.reloadWorkspace()
        let globalRefreshTokenBeforeRotation = state.imageRefreshToken
        let targetRefreshTokenBeforeRotation = state.imageRefreshToken(for: asset.id)
        let otherRefreshTokenBeforeRotation = state.imageRefreshToken(for: otherAsset.id)

        await state.rotateLocalAssetFiles([asset.id], quarterTurns: 1)

        let rotatedAsset = try #require(state.assets.first { $0.id == asset.id })
        let unchangedAsset = try #require(state.assets.first { $0.id == otherAsset.id })
        let imageRep = try #require(NSBitmapImageRep(data: Data(contentsOf: fileURL)))
        #expect(rotatedAsset.width == 20)
        #expect(rotatedAsset.height == 30)
        #expect(imageRep.pixelsWide == 20)
        #expect(imageRep.pixelsHigh == 30)
        #expect(unchangedAsset.width == 40)
        #expect(unchangedAsset.height == 24)
        #expect(try finderTagService.readTags(at: fileURL) == [tag])
        #expect(state.imageRefreshToken == globalRefreshTokenBeforeRotation)
        #expect(state.imageRefreshToken(for: asset.id) != targetRefreshTokenBeforeRotation)
        #expect(state.imageRefreshToken(for: otherAsset.id) == otherRefreshTokenBeforeRotation)
        #expect(state.rotationErrorMessage == nil)
    }

    @Test
    func rotationFailureLeavesPublishedDimensionsUnchanged() async {
        let library = LibraryFolder(displayName: "Rotation", path: "/tmp", columnIndex: 0)
        let asset = AssetRecord(
            libraryID: library.id,
            filename: "missing.png",
            relativePath: "missing.png",
            format: .png,
            fileSizeBytes: 1,
            width: 30,
            height: 20
        )
        let snapshot = WorkspaceSnapshot(
            libraries: [library],
            assets: [asset],
            compareGroups: [],
            keepFolderPath: "/tmp/Keep",
            rejectFolderPath: "/tmp/Reject"
        )
        let state = AppState(
            indexingService: RotationStaticIndexingService(snapshot: snapshot),
            assetFileRotationService: FailingRotationService()
        )
        await state.reloadWorkspace()

        await state.rotateLocalAssetFiles([asset.id], quarterTurns: 1)

        #expect(state.assets.first?.width == 30)
        #expect(state.assets.first?.height == 20)
        #expect(state.rotationErrorMessage != nil)
    }
}

private struct RotationStaticIndexingService: IndexingService {
    let snapshot: WorkspaceSnapshot

    func loadWorkspace() async throws -> WorkspaceSnapshot { snapshot }
}

private struct FailingRotationService: AssetFileRotating {
    func rotateFile(at url: URL, quarterTurns: Int) throws {
        throw RotationTestError.expectedFailure
    }
}

private enum RotationTestError: Error {
    case expectedFailure
}

private func writePNG(width: Int, height: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let data = bitmap.representation(using: .png, properties: [:]) else {
        throw RotationTestError.expectedFailure
    }
    try data.write(to: url)
}
