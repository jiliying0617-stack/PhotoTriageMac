import Foundation

public protocol WorkspaceRootsPersisting: Sendable {
    func clearRootPaths()
}

public final class UserDefaultsWorkspaceRootsStore: WorkspaceRootsPersisting, @unchecked Sendable {
    public let defaults: UserDefaults
    public let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "PhotoTriage.workspaceRootPaths"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func clearRootPaths() {
        defaults.removeObject(forKey: key)
    }
}

public struct NoopWorkspaceRootsStore: WorkspaceRootsPersisting {
    public init() {}

    public func clearRootPaths() {}
}
