import Foundation

public struct MockIndexingService: IndexingService {
    public init() {}

    public func loadWorkspace() async throws -> WorkspaceSnapshot {
        try await Task.sleep(for: .milliseconds(180))

        let libraries = [
            LibraryFolder(displayName: "原始图", path: "/Volumes/Photos/Originals", columnIndex: 0),
            LibraryFolder(displayName: "AI 精修", path: "/Volumes/Photos/Retouched", columnIndex: 1),
            LibraryFolder(displayName: "交付版", path: "/Volumes/Photos/Delivery", columnIndex: 2),
        ]

        let sampleAssets = WorkspaceFixtures.makeAssets(libraries: libraries)
        let groups = CompareGroupingService.buildGroups(
            libraries: libraries,
            assets: sampleAssets
        )

        return WorkspaceSnapshot(
            libraries: libraries,
            assets: sampleAssets,
            compareGroups: groups,
            keepFolderPath: "/Volumes/Photos/Keep",
            rejectFolderPath: "/Volumes/Photos/Reject",
        )
    }
}
