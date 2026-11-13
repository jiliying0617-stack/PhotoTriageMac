import Foundation

public struct LibraryFolder: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var displayName: String
    public var path: String
    public var columnIndex: Int

    public init(
        id: UUID = UUID(),
        displayName: String,
        path: String,
        columnIndex: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.columnIndex = columnIndex
    }
}
