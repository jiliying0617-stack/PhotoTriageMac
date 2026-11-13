import Foundation

public struct AppTag: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String

    public init(name: String) {
        self.id = name.lowercased()
        self.name = name
    }
}
