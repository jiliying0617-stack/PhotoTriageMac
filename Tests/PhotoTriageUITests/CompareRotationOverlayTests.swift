import AppKit
import Foundation
import ImageIO
import PhotoTriageCore
import Testing
@testable import PhotoTriageUI

@MainActor
struct CompareRotationOverlayTests {
    @Test(arguments: ["jpg", "png"])
    func localRotationUpdatesBaseAndBothRetainedOverlayLayers(fileExtension: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CompareRotationIntegration-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("second.\(fileExtension)")
        let otherURL = root.appendingPathComponent("first.\(fileExtension)")
        try writeFixture(url)
        try writeFixture(otherURL)
        let library = LibraryFolder(displayName: "Integration", path: root.path, columnIndex: 0)
        let assets = [otherURL, url].map {
            AssetRecord(libraryID: library.id, filename: $0.lastPathComponent, relativePath: $0.lastPathComponent,
                format: AssetFormat.infer(from: $0), fileSizeBytes: 1, width: 80, height: 40)
        }
        let state = AppState(indexingService: OverlayRotationIndex(snapshot: WorkspaceSnapshot(
            libraries: [library], assets: assets, compareGroups: [], keepFolderPath: root.path, rejectFolderPath: root.path)),
            assetFileRotationService: FileSystemAssetRotationService(backupRoot: root.appendingPathComponent("backup")))
        await state.reloadWorkspace()
        state.setSelection(assetIDs: Set(assets.map(\.id)))
        state.enterCompareMode()
        let targetID = try #require(state.compareAsset(atPane: 1)?.id)
        let unchangedID = assets[0].id
        let unchanged = CompareAssetImageHostView(frame: .zero)
        configure(unchanged, asset: assets[0], url: otherURL, token: state.imageRefreshToken(for: unchangedID))
        let main = CompareAssetImageHostView(frame: .zero)
        let overlay = CompareAssetImageHostView(frame: .zero)
        let instant = CompareAssetImageHostView(frame: .zero)
        let hosts = [main, overlay, instant]
        for host in hosts {
            configure(host, asset: assets[1], url: url, token: state.imageRefreshToken(for: targetID))
        }
        await settle()
        let unchangedImage = try #require(unchanged.displayedImage)
        let unchangedToken = state.imageRefreshToken(for: unchangedID)
        for turns in 1...4 {
            await state.rotateLocalAssetFiles([targetID])
            #expect(state.rotationErrorMessage == nil)
            let rotated = try #require(state.compareAsset(atPane: 1))
            for host in hosts {
                configure(host, asset: rotated, url: url, token: state.imageRefreshToken(for: targetID))
            }
            // Visibility transitions must never undo the local file rotation.
            instant.viewDidMoveToWindow()
            configure(instant, asset: rotated, url: url, token: state.imageRefreshToken(for: targetID))
            await settle()
            let expectedSize = turns % 2 == 1 ? NSSize(width: 40, height: 80) : NSSize(width: 80, height: 40)
            let referenceImage = try #require(PhotoImagePipeline.image(for: url, maxPixelSize: 80, cachePolicy: .bypass))
            let referencePixels = try pixels(referenceImage)
            let fileAfterRotation = try Data(contentsOf: url)
            for host in hosts {
                let displayed = try #require(host.displayedImage)
                #expect(displayed.size == expectedSize)
                #expect(try pixels(displayed) == referencePixels)
                for _ in 0..<5 {
                    host.alphaValue = 0
                    configure(host, asset: rotated, url: url, token: state.imageRefreshToken(for: targetID))
                    host.alphaValue = 1
                }
                #expect(host.displayedImage === displayed)
            }
            #expect(try Data(contentsOf: url) == fileAfterRotation)
            #expect(state.imageRefreshToken(for: unchangedID) == unchangedToken)
            #expect(unchanged.displayedImage === unchangedImage)
        }
    }

    @Test func interruptedHiddenOverlayReloadDoesNotTreatOldFrameAsCurrent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CompareRotationOverlay-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("frame.png")
        try Data("isolated-loader-fixture".utf8).write(to: url)
        let before = NSImage(size: NSSize(width: 80, height: 40))
        let after = NSImage(size: NSSize(width: 40, height: 80))
        var calls = 0
        let host = CompareAssetImageHostView(frame: .zero) { _, _, _ in
            calls += 1
            if calls == 1 { return before }
            try? await Task.sleep(for: .milliseconds(60))
            return after
        }
        let asset = AssetRecord(libraryID: UUID(), filename: "frame.png", relativePath: "frame.png",
            format: .png, fileSizeBytes: 1, width: 80, height: 40)
        let firstToken = UUID(), rotatedToken = UUID()
        configure(host, asset: asset, url: url, token: firstToken)
        await settle()
        #expect(host.displayedImage === before)
        configure(host, asset: asset, url: url, token: rotatedToken)
        await Task.yield()
        // A retained Q layer can be detached/reinserted or have an in-flight request
        // replaced while its old frame stays visible. This must not mark it loaded.
        host.viewDidMoveToWindow()
        configure(host, asset: asset, url: url, token: rotatedToken)
        await settle()
        #expect(host.displayedImage === after)
        #expect(calls >= 3)
    }

    @Test func newerRequestCancelsOlderCompletionWithoutRevertingOrientation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CompareRotationOverlay-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("frame.png")
        try Data("isolated-loader-fixture".utf8).write(to: url)
        let before = NSImage(size: NSSize(width: 80, height: 40))
        let after = NSImage(size: NSSize(width: 40, height: 80))
        var calls = 0
        let host = CompareAssetImageHostView(frame: .zero) { _, _, _ in
            calls += 1
            if calls == 1 {
                try? await Task.sleep(for: .milliseconds(80))
                return before
            }
            return after
        }
        let asset = AssetRecord(libraryID: UUID(), filename: "frame.png", relativePath: "frame.png",
            format: .png, fileSizeBytes: 1, width: 80, height: 40)
        configure(host, asset: asset, url: url, token: UUID())
        await Task.yield()
        configure(host, asset: asset, url: url, token: UUID())
        await settle()
        #expect(host.displayedImage === after)
    }

    private func configure(_ host: CompareAssetImageHostView, asset: AssetRecord, url: URL, token: UUID) {
        host.configure(asset: asset, fileURL: url, refreshToken: token, maxPixelSize: 80,
            contentMode: .fit, locksToBounds: false, showsLoadingIndicator: false)
    }
    private func settle() async { try? await Task.sleep(for: .milliseconds(150)) }

    private func writeFixture(_ url: URL) throws {
        var bytes = [UInt8](repeating: 255, count: 80 * 40 * 4)
        for y in 0..<40 {
            for x in 0..<80 {
                let offset = (y * 80 + x) * 4
                bytes[offset] = UInt8(x * 3)
                bytes[offset + 1] = UInt8(y * 6)
                bytes[offset + 2] = x < 30 && y < 20 ? 0 : 255
            }
        }
        let image = try #require(CGImage(width: 80, height: 40, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 320,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let type = (url.pathExtension == "jpg" ? "public.jpeg" : "public.png") as CFString
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func pixels(_ image: NSImage) throws -> Data {
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var bytes = Data(count: cgImage.width * cgImage.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return bytes
    }
}

private struct OverlayRotationIndex: IndexingService {
    let snapshot: WorkspaceSnapshot
    func loadWorkspace() async throws -> WorkspaceSnapshot { snapshot }
}
