import Foundation

public struct WorkspaceSnapshot: Sendable {
    public var libraries: [LibraryFolder]
    public var assets: [AssetRecord]
    public var compareGroups: [CompareGroup]
    public var keepFolderPath: String
    public var rejectFolderPath: String

    public init(
        libraries: [LibraryFolder],
        assets: [AssetRecord],
        compareGroups: [CompareGroup],
        keepFolderPath: String,
        rejectFolderPath: String
    ) {
        self.libraries = libraries
        self.assets = assets
        self.compareGroups = compareGroups
        self.keepFolderPath = keepFolderPath
        self.rejectFolderPath = rejectFolderPath
    }
}
