import Foundation

public struct ExportProgress: Sendable {
    public var completed: Int
    public var total: Int
    public init(completed: Int, total: Int) { self.completed = completed; self.total = total }
}

public struct ExportFailure: Sendable, Equatable {
    public var sourcePath: String
    public var message: String
}

public struct ExportRequest: Sendable {
    public var libraries: [LibraryFolder]
    public var assets: [AssetRecord]
    public var keepFolderPath: String
    public var rejectFolderPath: String
    public var pendingFolderPath: String
    public var priorityTagFolderPaths: [PriorityTag: String]
    public var finderTagFolderPaths: [FinderTagColor: String]
    public var includeKeep: Bool
    public var includeReject: Bool
    public var includePending: Bool
    public var includedPriorityTags: Set<PriorityTag>
    public var includedFinderTagColors: Set<FinderTagColor>
    public var onProgress: (@Sendable (ExportProgress) -> Void)?

    public init(
        libraries: [LibraryFolder],
        assets: [AssetRecord],
        keepFolderPath: String,
        rejectFolderPath: String,
        pendingFolderPath: String? = nil,
        priorityTagFolderPaths: [PriorityTag: String] = [:],
        finderTagFolderPaths: [FinderTagColor: String] = [:],
        includeKeep: Bool = true,
        includeReject: Bool = true,
        includePending: Bool,
        includedPriorityTags: Set<PriorityTag> = [],
        includedFinderTagColors: Set<FinderTagColor> = [],
        onProgress: (@Sendable (ExportProgress) -> Void)? = nil
    ) {
        self.libraries = libraries
        self.assets = assets
        self.keepFolderPath = keepFolderPath
        self.rejectFolderPath = rejectFolderPath
        self.pendingFolderPath = pendingFolderPath ?? URL(fileURLWithPath: rejectFolderPath, isDirectory: true)
            .deletingLastPathComponent()
            .appendingPathComponent("未处理", isDirectory: true)
            .path
        self.priorityTagFolderPaths = priorityTagFolderPaths
        self.finderTagFolderPaths = finderTagFolderPaths
        self.includeKeep = includeKeep
        self.includeReject = includeReject
        self.includePending = includePending
        self.includedPriorityTags = includedPriorityTags
        self.includedFinderTagColors = includedFinderTagColors
        self.onProgress = onProgress
    }
}

public struct ExportExecutionSummary: Sendable, Equatable {
    public var exportedCount: Int
    public var keepCount: Int
    public var rejectCount: Int
    public var pendingCount: Int
    public var priorityTagSummary: PriorityTagSummary
    public var finderTagColorSummary: FinderTagColorSummary
    public var renamedConflictCount: Int
    public var skippedCount = 0
    public var failures: [ExportFailure] = []
    public var wasCancelled = false
    public var receiptPath: String?

    public init(
        exportedCount: Int,
        keepCount: Int,
        rejectCount: Int,
        pendingCount: Int,
        priorityTagSummary: PriorityTagSummary = PriorityTagSummary(),
        finderTagColorSummary: FinderTagColorSummary = FinderTagColorSummary(),
        renamedConflictCount: Int = 0
    ) {
        self.exportedCount = exportedCount
        self.keepCount = keepCount
        self.rejectCount = rejectCount
        self.pendingCount = pendingCount
        self.priorityTagSummary = priorityTagSummary
        self.finderTagColorSummary = finderTagColorSummary
        self.renamedConflictCount = renamedConflictCount
    }

    public var reviewedCount: Int {
        keepCount + rejectCount
    }

    public var decisionCount: Int {
        keepCount + rejectCount + pendingCount
    }

    public var passRate: Double {
        guard decisionCount > 0 else { return 0 }
        return Double(keepCount + pendingCount) / Double(decisionCount)
    }
}

public enum ExportExecutionError: Error, LocalizedError, Sendable {
    case missingLibrary(UUID)
    case missingSourceAsset(String)

    public var errorDescription: String? {
        switch self {
        case let .missingLibrary(libraryID):
            return "Missing library for asset export: \(libraryID.uuidString)"
        case let .missingSourceAsset(path):
            return "Missing source asset at path: \(path)"
        }
    }
}
