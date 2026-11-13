import Foundation

public struct FolderTreeNode: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(libraryID.uuidString):\(relativePath)" }
    public let libraryID: UUID
    public let name: String
    public let relativePath: String
    public let assetCount: Int
    public let children: [FolderTreeNode]

    public init(
        libraryID: UUID,
        name: String,
        relativePath: String,
        assetCount: Int,
        children: [FolderTreeNode]
    ) {
        self.libraryID = libraryID
        self.name = name
        self.relativePath = relativePath
        self.assetCount = assetCount
        self.children = children
    }
}
