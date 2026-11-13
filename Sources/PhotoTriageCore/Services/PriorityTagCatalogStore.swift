import Foundation

public protocol PriorityTagCatalogPersisting: Sendable {
    func load() throws -> [PriorityTagDefinition]
    func save(_ definitions: [PriorityTagDefinition]) throws
}

public struct NoopPriorityTagCatalogStore: PriorityTagCatalogPersisting {
    public init() {}
    public func load() throws -> [PriorityTagDefinition] { PriorityTagDefinition.defaults }
    public func save(_ definitions: [PriorityTagDefinition]) throws {}
}

public final class UserDefaultsPriorityTagCatalogStore: PriorityTagCatalogPersisting, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "PhotoTriage.priorityTagCatalog.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> [PriorityTagDefinition] {
        guard let data = defaults.data(forKey: key) else { return PriorityTagDefinition.defaults }
        return try JSONDecoder().decode([PriorityTagDefinition].self, from: data)
    }

    public func save(_ definitions: [PriorityTagDefinition]) throws {
        defaults.set(try JSONEncoder().encode(definitions), forKey: key)
    }
}
