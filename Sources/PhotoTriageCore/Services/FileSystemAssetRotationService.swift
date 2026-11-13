import Foundation
import CryptoKit
import ImageIO

public struct FileSystemAssetRotationService: AssetFileRotating {
    private let backupRoot: URL

    public init(backupRoot: URL? = nil) {
        self.backupRoot = backupRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhotoTriageMac/RotationOriginals", isDirectory: true)
    }

    public func rotateFile(at url: URL, quarterTurns: Int) throws {
        let normalizedTurns = ((quarterTurns % 4) + 4) % 4
        guard normalizedTurns != 0 else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AssetFileRotationError.missingFile(url.path)
        }

        let manager = FileManager.default
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) else {
            throw AssetFileRotationError.commandFailed(path: url.path, detail: "无法读取图片，原文件未改动")
        }
        // Keep the original outside indexed source folders. Never silently re-encode JPEG/HEIF.
        let pathKey = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let backupFolder = backupRoot.appendingPathComponent(pathKey, isDirectory: true)
        let original = backupFolder.appendingPathComponent(url.lastPathComponent)
        try manager.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: original.path) {
            try manager.copyItem(at: url, to: original)
            try Data(url.path.utf8).write(to: backupFolder.appendingPathComponent("原路径.txt"), options: .atomic)
        }
        let staged = url.deletingLastPathComponent().appendingPathComponent(".photo-triage-\(UUID().uuidString).\(url.pathExtension)")
        defer { try? manager.removeItem(at: staged) }

        if (type as String) == "public.png" {
            // PNG uses lossless pixel rotation; also works with readers ignoring PNG EXIF.
            try manager.copyItem(at: url, to: staged)
            try rotatePNG(at: staged, normalizedTurns: normalizedTurns)
        } else {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            var orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            let clockwise = [1: 6, 2: 7, 3: 8, 4: 5, 5: 2, 6: 3, 7: 4, 8: 1]
            for _ in 0..<normalizedTurns { orientation = clockwise[orientation] ?? 6 }
            guard let destination = CGImageDestinationCreateWithURL(staged as CFURL, type, CGImageSourceGetCount(source), nil) else {
                throw AssetFileRotationError.commandFailed(path: url.path, detail: "此格式不支持安全旋转，原文件未改动")
            }
            var error: Unmanaged<CFError>?
            guard CGImageDestinationCopyImageSource(destination, source,
                [kCGImageDestinationOrientation: orientation] as CFDictionary, &error) else {
                let detail = error?.takeRetainedValue().localizedDescription ?? "此格式不支持无损旋转"
                throw AssetFileRotationError.commandFailed(path: url.path, detail: detail + "；原文件未改动")
            }
        }
        guard let validation = CGImageSourceCreateWithURL(staged as CFURL, nil),
              CGImageSourceGetCount(validation) == CGImageSourceGetCount(source),
              AssetMetadataReader.metadata(for: staged) != nil else {
            throw AssetFileRotationError.commandFailed(path: url.path, detail: "旋转结果校验失败，原文件未改动")
        }
        _ = try manager.replaceItemAt(url, withItemAt: staged)
        try manager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func rotatePNG(at url: URL, normalizedTurns: Int) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["--rotate", "\(normalizedTurns * 90)", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AssetFileRotationError.commandFailed(path: url.path, detail: detail ?? "未知错误")
        }
    }
}

public enum AssetFileRotationError: Error, LocalizedError, Sendable {
    case missingFile(String)
    case commandFailed(path: String, detail: String)
    case rollbackFailed(recoveryDirectory: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case let .missingFile(path):
            "找不到需要旋转的本地图片：\(path)"
        case let .commandFailed(path, detail):
            "本地图片旋转失败：\(path)（\(detail)）"
        case let .rollbackFailed(recoveryDirectory, detail):
            "旋转未完成，自动恢复失败：\(detail)。原文件备份保留在：\(recoveryDirectory)。请先从备份恢复，再继续旋转。"
        }
    }
}
