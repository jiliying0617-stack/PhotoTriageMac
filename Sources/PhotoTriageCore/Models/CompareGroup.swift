import Foundation

public struct CompareSlot: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(library.id.uuidString)-\(asset?.id.uuidString ?? "missing")" }
    public var library: LibraryFolder
    public var asset: AssetRecord?

    public init(library: LibraryFolder, asset: AssetRecord?) {
        self.library = library
        self.asset = asset
    }
}

public struct CompareGroup: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var filenameKey: String
    public var relativePath: String
    public var displayName: String
    public var slots: [CompareSlot]

    public init(filenameKey: String, relativePath: String, displayName: String, slots: [CompareSlot]) {
        self.id = relativePath.lowercased()
        self.filenameKey = filenameKey
        self.relativePath = relativePath
        self.displayName = displayName
        self.slots = slots
    }
}
