import Foundation

public enum AssetSortMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case addedDate
    case filename

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .addedDate:
            return "按添加时间"
        case .filename:
            return "按文件名"
        }
    }
}
