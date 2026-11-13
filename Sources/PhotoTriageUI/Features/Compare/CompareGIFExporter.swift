import Foundation
import PhotoTriageCore
import SwiftUI

#if canImport(AppKit)
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct CompareGIFExportRequest {
    let viewport: CGSize
    let zoomScale: CGFloat
    let pan: CGSize
    let contentInset: CGFloat

    init(
        viewport: CGSize,
        zoomScale: CGFloat,
        pan: CGSize,
        contentInset: CGFloat,
        displayScale: CGFloat = 1
    ) {
        self.viewport = viewport
        self.zoomScale = zoomScale
        self.pan = pan
        self.contentInset = contentInset
        self.displayScale = displayScale
    }

    let displayScale: CGFloat
}

struct CompareGIFExportItem {
    let asset: AssetRecord
    let fileURL: URL
}

struct CompareGIFExportProgress: Sendable {
    let completedFrames: Int
    let totalFrames: Int
    let message: String
}

enum CompareGIFExporter {
    private static let exportQueue = DispatchQueue(label: "com.jiliying.phototriage.gif-export", qos: .userInitiated)
    @MainActor private static var isExporting = false
    private static let frameDuration = 0.75
    private static let gifDitherStrength: CGFloat = 5
    private static let gifDitherMatrix: [[CGFloat]] = [
        [0, 32, 8, 40, 2, 34, 10, 42],
        [48, 16, 56, 24, 50, 18, 58, 26],
        [12, 44, 4, 36, 14, 46, 6, 38],
        [60, 28, 52, 20, 62, 30, 54, 22],
        [3, 35, 11, 43, 1, 33, 9, 41],
        [51, 19, 59, 27, 49, 17, 57, 25],
        [15, 47, 7, 39, 13, 45, 5, 37],
        [63, 31, 55, 23, 61, 29, 53, 21]
    ]

    @MainActor
    static func saveWithPanel(items: [CompareGIFExportItem], request: CompareGIFExportRequest) {
        guard items.count >= 2, !isExporting else {
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.title = "保存对比 GIF"
        panel.nameFieldStringValue = defaultFilename()
        panel.allowedContentTypes = [.gif]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let outputURL = panel.url else {
            return
        }

        let progressController = CompareGIFExportProgressWindowController(totalFrames: items.count)
        progressController.show()
        isExporting = true

        Task { @MainActor in
            defer { isExporting = false }
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    exportQueue.async {
                        do {
                            try writeGIF(items: items, request: request, to: outputURL) { progress in
                                Task { @MainActor in progressController.update(progress) }
                            }
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                progressController.complete()
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } catch {
                progressController.close()
                presentSaveError(error)
            }
        }
    }

    static func writeGIF(
        items: [CompareGIFExportItem],
        request: CompareGIFExportRequest,
        to outputURL: URL,
        progress: (@Sendable (CompareGIFExportProgress) -> Void)? = nil
    ) throws {
        guard !items.isEmpty, request.viewport.width.isFinite, request.viewport.height.isFinite,
              request.viewport.width > 0, request.viewport.height > 0,
              request.displayScale.isFinite, request.zoomScale.isFinite, request.zoomScale > 0,
              request.pan.width.isFinite, request.pan.height.isFinite else {
            throw CompareGIFExportError.invalidViewport
        }
        let frameSize = exportFrameSize(for: request, items: items)
        // Do not silently reduce export quality. Reject an unsafe allocation before
        // ImageIO starts retaining frames or touches the requested destination.
        let estimatedBytes = Double(frameSize.width) * Double(frameSize.height) * (20 + 4 * Double(items.count))
        let budget = min(Double(ProcessInfo.processInfo.physicalMemory) / 4, 2_147_483_648)
        guard frameSize.width.isFinite, frameSize.height.isFinite,
              frameSize.width <= 65_535, frameSize.height <= 65_535,
              estimatedBytes <= budget else {
            throw CompareGIFExportError.memoryLimit
        }
        // ImageIO may create its own sibling scratch file before finalization.
        // Isolate all files for this export so every failure can clean them up.
        let stagingDirectory = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".phototriage-gif-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }
        let temporaryURL = stagingDirectory.appendingPathComponent("export.gif")

        // ImageIO can retain its URL consumer in an autorelease pool. Drain it
        // before moving/removing the temporary file, including failure paths.
        try autoreleasepool {
        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            UTType.gif.identifier as CFString,
            items.count,
            nil
        ) else {
            throw CompareGIFExportError.destinationUnavailable
        }

        CGImageDestinationSetProperties(
            destination,
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0
                ]
            ] as CFDictionary
        )

        progress?(
            CompareGIFExportProgress(
                completedFrames: 0,
                totalFrames: items.count,
                message: "准备导出"
            )
        )

        for (index, item) in items.enumerated() {
            try autoreleasepool {
                guard let renderedFrame = renderFrame(item: item, request: request, frameSize: frameSize),
                      let frame = ditheredFrameForGIF(renderedFrame) else {
                    throw CompareGIFExportError.frameRenderFailed(item.asset.filename)
                }

                CGImageDestinationAddImage(
                    destination,
                    frame,
                    [
                        kCGImagePropertyGIFDictionary: [
                            kCGImagePropertyGIFDelayTime: frameDuration
                        ]
                    ] as CFDictionary
                )
            }

            progress?(
                CompareGIFExportProgress(
                    completedFrames: index + 1,
                    totalFrames: items.count,
                    message: "已渲染 \(index + 1)/\(items.count)"
                )
            )
        }

        guard CGImageDestinationFinalize(destination) else {
            throw CompareGIFExportError.finalizeFailed
        }
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        }
    }

    private static func renderFrame(
        item: CompareGIFExportItem,
        request: CompareGIFExportRequest,
        frameSize: CGSize
    ) -> CGImage? {
        let scaledRequest = scaledExportRequest(request: request, frameSize: frameSize)
        let sourceImageSize = resolvedPixelSize(for: item)
        let contentSize = CompareLayoutMetrics.fittedImageSize(
            imageSize: sourceImageSize,
            viewport: scaledRequest.viewport,
            zoomScale: scaledRequest.zoomScale
        )
        guard let image = PhotoImagePipeline.fullResolutionCGImage(for: item.fileURL) else {
            return nil
        }

        let panContentSize = CompareLayoutMetrics.pannableContentSize(
            fittedContentSize: contentSize,
            viewport: scaledRequest.viewport,
            zoomScale: scaledRequest.zoomScale
        )
        let actualOffset = CompareLayoutMetrics.actualPanOffset(
            normalizedPan: scaledRequest.pan,
            viewport: scaledRequest.viewport,
            contentSize: panContentSize
        )

        let frameRect = CGRect(origin: .zero, size: frameSize)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(frameSize.width.rounded()),
            height: Int(frameSize.height.rounded()),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 0.035, alpha: 1))
        context.fill(frameRect)
        context.translateBy(x: 0, y: frameSize.height)
        context.scaleBy(x: 1, y: -1)

        let targetRect = CGRect(
            x: (frameSize.width - contentSize.width) * 0.5 + actualOffset.width,
            y: (frameSize.height - contentSize.height) * 0.5 + actualOffset.height,
            width: contentSize.width,
            height: contentSize.height
        )
        draw(
            image,
            rotationDegrees: item.asset.normalizedRotationDegrees,
            targetRect: targetRect,
            in: context
        )

        return context.makeImage()
    }

    private static func ditheredFrameForGIF(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return image }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // The context owns this allocation. A pointer produced by passing &array
        // to CGContext only lives for that initializer call and must not escape.
        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: height * context.bytesPerRow)
            for y in 0..<height {
                let rowOffset = y * context.bytesPerRow
                for x in 0..<width {
                    let offset = rowOffset + (x * bytesPerPixel)
                    let table = gifDitherLookup[(y & 7) * 8 + (x & 7)]
                    buffer[offset] = table[Int(buffer[offset])]
                    buffer[offset + 1] = table[Int(buffer[offset + 1])]
                    buffer[offset + 2] = table[Int(buffer[offset + 2])]
                }
            }

        return context.makeImage()
    }

    private static let gifDitherLookup: [[UInt8]] = gifDitherMatrix.flatMap { row in
        row.map { value in
            let adjustment = (((value + 0.5) / 64) - 0.5) * gifDitherStrength
            return (0...255).map { adjustedGIFChannel(UInt8($0), by: adjustment) }
        }
    }

    private static func adjustedGIFChannel(_ value: UInt8, by adjustment: CGFloat) -> UInt8 {
        UInt8(min(max(CGFloat(value) + adjustment, 0), 255).rounded())
    }

    private static func draw(_ image: CGImage, rotationDegrees: Int, targetRect: CGRect, in context: CGContext) {
        let rotation = AssetRecord.normalizedRotationDegrees(rotationDegrees)
        context.saveGState()
        context.translateBy(x: targetRect.midX, y: targetRect.midY)
        context.rotate(by: CGFloat(rotation) * .pi / 180)

        let targetSize = rotation == 90 || rotation == 270
            ? CGSize(width: targetRect.height, height: targetRect.width)
            : CGSize(width: targetRect.width, height: targetRect.height)
        let imageRect = CGRect(
            x: -targetSize.width * 0.5,
            y: -targetSize.height * 0.5,
            width: targetSize.width,
            height: targetSize.height
        )

        context.translateBy(x: imageRect.minX, y: imageRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(
            image,
            in: CGRect(origin: .zero, size: imageRect.size)
        )
        context.restoreGState()
    }

    private static func scaledExportRequest(request: CompareGIFExportRequest, frameSize: CGSize) -> CompareGIFExportRequest {
        let scale = min(frameSize.width / max(request.viewport.width, 1), frameSize.height / max(request.viewport.height, 1))
        return CompareGIFExportRequest(
            viewport: frameSize,
            zoomScale: request.zoomScale,
            pan: request.pan,
            contentInset: request.contentInset * scale,
            displayScale: 1
        )
    }

    private static func exportFrameSize(for request: CompareGIFExportRequest, items: [CompareGIFExportItem]) -> CGSize {
        let scale = max(sourcePixelExportScale(for: request, items: items), request.displayScale, 1)
        return CGSize(
            width: max((request.viewport.width * scale).rounded(), 1),
            height: max((request.viewport.height * scale).rounded(), 1)
        )
    }

    private static func sourcePixelExportScale(for request: CompareGIFExportRequest, items: [CompareGIFExportItem]) -> CGFloat {
        let viewport = request.viewport
        guard viewport.width > 0, viewport.height > 0 else { return 1 }

        return items.reduce(CGFloat(1)) { currentScale, item in
            let imageSize = resolvedPixelSize(for: item)
            guard imageSize.width > 0, imageSize.height > 0 else { return currentScale }

            let fitScale = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
            guard fitScale > 0 else { return currentScale }

            let sourcePixelScale = 1 / fitScale
            return max(currentScale, sourcePixelScale)
        }
    }

    private static func resolvedPixelSize(for item: CompareGIFExportItem) -> CGSize {
        if let filePixelSize = PhotoImagePipeline.pixelSize(for: item.fileURL) {
            return filePixelSize
        }

        return item.asset.pixelSize
    }

    private static func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "对比动图-\(formatter.string(from: Date())).gif"
    }

    @MainActor
    private static func presentSaveError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "GIF 保存失败"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

enum CompareGIFExportError: LocalizedError {
    case invalidViewport
    case destinationUnavailable
    case frameRenderFailed(String)
    case finalizeFailed
    case memoryLimit

    var errorDescription: String? {
        switch self {
        case .invalidViewport:
            return "当前窗口范围无效。"
        case .destinationUnavailable:
            return "无法创建 GIF 文件。"
        case let .frameRenderFailed(filename):
            return "无法读取或渲染图片：\(filename)"
        case .finalizeFailed:
            return "GIF 写入未能完成。"
        case .memoryLimit:
            return "此组原图 GIF 超过安全内存或尺寸范围，请减少对比图片数量后重试；原图和已有导出文件未修改。"
        }
    }
}

@MainActor
final class CompareGIFExportProgressWindowController {
    private let totalFrames: Int
    private let window: NSWindow
    private let progressIndicator = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "正在导出 GIF")
    private let detailLabel = NSTextField(labelWithString: "准备导出")
    private(set) var isCompleted = false
    var isVisible: Bool { window.isVisible }

    init(totalFrames: Int) {
        self.totalFrames = max(totalFrames, 1)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 138))
        window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GIF 导出"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = contentView

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 13, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = Double(self.totalFrames)
        progressIndicator.doubleValue = 0
        progressIndicator.controlSize = .regular
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(detailLabel)
        contentView.addSubview(progressIndicator)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),

            progressIndicator.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            progressIndicator.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 18)
        ])
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func update(_ progress: CompareGIFExportProgress) {
        guard !isCompleted else { return }
        progressIndicator.maxValue = Double(max(progress.totalFrames, 1))
        progressIndicator.doubleValue = Double(progress.completedFrames)
        detailLabel.stringValue = progress.message
    }

    func complete() {
        isCompleted = true
        progressIndicator.doubleValue = Double(totalFrames)
        detailLabel.stringValue = "导出完成"
        // Close while the owning task still retains the controller; a weak delayed
        // callback can outlive it and leave an orphaned floating window behind.
        close()
    }

    func close() {
        window.close()
    }
}
#endif
