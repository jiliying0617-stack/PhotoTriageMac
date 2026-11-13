import Foundation

public enum RatingState: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case pending
    case keep
    case reject

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pending:
            "待定"
        case .keep:
            "保留"
        case .reject:
            "淘汰"
        }
    }
}
