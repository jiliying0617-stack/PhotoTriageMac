import Foundation

public enum AssetFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case jpg
    case png
    case heic
    case webp
    case cr2
    case arw
    case dng
    case unknown

    public static let supportedFileExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "webp", "cr2", "arw", "dng"
    ]

    public var id: String { rawValue }

    public var badge: String {
        rawValue.uppercased()
    }

    public var isRaw: Bool {
        switch self {
        case .cr2, .arw, .dng:
            true
        default:
            false
        }
    }

    public static func infer(from fileURL: URL) -> AssetFormat {
        let ext = fileURL.pathExtension.lowercased()
        return switch ext {
        case "jpg", "jpeg": .jpg
        case "png": .png
        case "heic": .heic
        case "webp": .webp
        case "cr2": .cr2
        case "arw": .arw
        case "dng": .dng
        default: .unknown
        }
    }
}
