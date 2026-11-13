import Foundation

public protocol IndexingService: Sendable {
    func loadWorkspace() async throws -> WorkspaceSnapshot
    func refreshWorkspace(_ previous: WorkspaceSnapshot, changedPaths: Set<String>) async throws -> WorkspaceSnapshot
    func loadWorkspaceSnapshots() -> AsyncThrowingStream<WorkspaceSnapshot, Error>
    func loadMetadata(
        for assets: [AssetRecord],
        libraries: [LibraryFolder]
    ) async throws -> [UUID: AssetMetadata]
}

public extension IndexingService {
    func refreshWorkspace(_ previous: WorkspaceSnapshot, changedPaths: Set<String>) async throws -> WorkspaceSnapshot {
        try await loadWorkspace()
    }

    func loadWorkspaceSnapshots() -> AsyncThrowingStream<WorkspaceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(try await loadWorkspace())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func loadMetadata(
        for assets: [AssetRecord],
        libraries: [LibraryFolder]
    ) async throws -> [UUID: AssetMetadata] {
        [:]
    }
}

public protocol FinderTagSyncing: Sendable {
    func readTags(at url: URL) throws -> [FinderTag]
    func writeTags(_ tags: [FinderTag], at url: URL) throws
}

public protocol AssetFileRotating: Sendable {
    func rotateFile(at url: URL, quarterTurns: Int) throws
}

public protocol TrashManaging: Sendable {
    func moveToTrash(_ assets: [AssetRecord]) async throws
}

public protocol ExportPlanning: Sendable {
    func buildExportBuckets(
        from assets: [AssetRecord],
        includePending: Bool
    ) -> [RatingState: [AssetRecord]]
}

public protocol ExportExecuting: Sendable {
    func export(_ request: ExportRequest) async throws -> ExportExecutionSummary
}

public protocol AssetInspectionService: Sendable {
    func revealInFinder(_ url: URL)
    func quickLook(_ url: URL)
}

public struct NoopAssetInspectionService: AssetInspectionService {
    public init() {}

    public func revealInFinder(_ url: URL) {}

    public func quickLook(_ url: URL) {}
}
