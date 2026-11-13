import Foundation

public enum WorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case grid
    case compare

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .grid:
            "网格"
        case .compare:
            "对比"
        }
    }
}
