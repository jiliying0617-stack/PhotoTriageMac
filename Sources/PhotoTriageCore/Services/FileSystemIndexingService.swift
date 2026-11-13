import Foundation

/// Cumulative indexing snapshots need a bounded buffer and consumer-owned work.
enum WorkspaceSnapshotStream {
    static func make(
        produce: @escaping @Sendable (AsyncThrowingStream<WorkspaceSnapshot, Error>.Continuation) async throws -> Void
    ) -> AsyncThrowingStream<WorkspaceSnapshot, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let producer = Task {
                do {
                    try Task.checkCancellation()
                    try await produce(continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }
}

public struct FileSystemIndexingService: IndexingService {
    public let rootPaths: [String]
    public let keepFolderName: String
    public let rejectFolderName: String
    public let assetBatchSize: Int
    /// Controls how often the streaming loader publishes a complete workspace snapshot.
    ///
    /// Finder tag reads still happen in `assetBatchSize` batches, but publishing every
    /// small batch makes AppState rebuild all of its indexes and SwiftUI redraw the grid
    /// repeatedly.  Larger workspaces therefore use a coarser publication interval.
    public let snapshotYieldInterval: Int
    /// Legacy metadata support is opt-in for the app's P-tag-only workflow.
    public let readsFinderTags: Bool
    private let finderTagService: any FinderTagSyncing

    public init(
        rootPaths: [String],
        keepFolderName: String = "Keep",
        rejectFolderName: String = "Reject",
        assetBatchSize: Int = 512,
        snapshotYieldInterval: Int? = nil,
        finderTagService: any FinderTagSyncing = FileSystemFinderTagService(),
        readsFinderTags: Bool = true
    ) {
        self.rootPaths = rootPaths
        self.keepFolderName = keepFolderName
        self.rejectFolderName = rejectFolderName
        self.assetBatchSize = max(assetBatchSize, 1)
        // Keep tiny batches fully streamable for tests and small folders.  For normal
        // batches, publish at most about five snapshots for a 20K-image workspace.
        self.snapshotYieldInterval = max(
            snapshotYieldInterval ?? (assetBatchSize < 128 ? max(assetBatchSize, 1) : 4_096),
            1
        )
        self.finderTagService = finderTagService
        self.readsFinderTags = readsFinderTags
    }

    public func loadWorkspace() async throws -> WorkspaceSnapshot {
        let resolvedRoots = rootPaths.compactMap(resolveDirectoryURL(from:))
        let libraries = makeLibraries(from: resolvedRoots)
        var assets: [AssetRecord] = []

        for library in libraries {
            let root = URL(fileURLWithPath: library.path, isDirectory: true)
            try await scanAssetBatches(in: root, libraryID: library.id) { batch in
                assets.append(contentsOf: batch)
            }
        }

        return makeSnapshot(libraries: libraries, assets: assets, resolvedRoots: resolvedRoots)
    }

    public func loadWorkspaceSnapshots() -> AsyncThrowingStream<WorkspaceSnapshot, Error> {
        // Snapshots are cumulative. A slow main-thread consumer only needs the
        // newest one; retaining every previous full array multiplies memory use.
        WorkspaceSnapshotStream.make { continuation in
            try Task.checkCancellation()
            let resolvedRoots = rootPaths.compactMap(resolveDirectoryURL(from:))
            let libraries = makeLibraries(from: resolvedRoots)
            var assets: [AssetRecord] = []
            var assetsSinceLastSnapshot = 0
            var lastPublishedAssetCount = 0

            continuation.yield(makeSnapshot(libraries: libraries, assets: assets, resolvedRoots: resolvedRoots))

            for library in libraries {
                let root = URL(fileURLWithPath: library.path, isDirectory: true)
                try await scanAssetBatches(in: root, libraryID: library.id) { batch in
                    assets.append(contentsOf: batch)
                    assetsSinceLastSnapshot += batch.count
                    guard assetsSinceLastSnapshot >= snapshotYieldInterval else { return }

                    continuation.yield(makeSnapshot(libraries: libraries, assets: assets, resolvedRoots: resolvedRoots))
                    lastPublishedAssetCount = assets.count
                    assetsSinceLastSnapshot = 0
                }
            }

            // Always publish the final partial interval so consumers see every
            // indexed asset even when the total is below the interval or does
            // not divide evenly into it.
            if assets.count != lastPublishedAssetCount {
                continuation.yield(makeSnapshot(libraries: libraries, assets: assets, resolvedRoots: resolvedRoots))
            }
        }
    }

    public func loadMetadata(
        for assets: [AssetRecord],
        libraries: [LibraryFolder]
    ) async throws -> [UUID: AssetMetadata] {
        let librariesByID = Dictionary(uniqueKeysWithValues: libraries.map { ($0.id, $0.path) })
        var metadataByAssetID: [UUID: AssetMetadata] = [:]
        metadataByAssetID.reserveCapacity(assets.count)

        for asset in assets {
            guard asset.width <= 0 || asset.height <= 0,
                  let libraryPath = librariesByID[asset.libraryID] else {
                continue
            }

            let fileURL = URL(fileURLWithPath: libraryPath, isDirectory: true)
                .appendingPathComponent(asset.relativePath)
            if let metadata = AssetMetadataReader.metadata(for: fileURL) {
                metadataByAssetID[asset.id] = metadata
            }
        }

        return metadataByAssetID
    }

    public func refreshWorkspace(_ previous: WorkspaceSnapshot, changedPaths: Set<String>) async throws -> WorkspaceSnapshot {
        guard changedPaths.count <= 256 else { return try await loadWorkspace() }
        var updated = previous.assets
        for path in changedPaths.sorted() {
            try Task.checkCancellation()
            let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            guard !url.pathComponents.contains(where: { $0.hasPrefix(".") }),
                  let library = previous.libraries.first(where: { url.path.hasPrefix($0.path + "/") }) else { continue }
            let relative = String(url.path.dropFirst(library.path.count + 1))
            var isDirectory = ObjCBool(false)
            if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                updated.removeAll { $0.libraryID == library.id && ($0.relativePath == relative || $0.relativePath.hasPrefix(relative + "/")) }
                continue
            }
            if isDirectory.boolValue { return try await loadWorkspace() }
            let format = AssetFormat.infer(from: url)
            guard format != .unknown else { continue }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .creationDateKey])
            let tags = readsFinderTags ? (try? finderTagService.readTags(at: url)) ?? [] : []
            let index = updated.firstIndex { $0.libraryID == library.id && $0.relativePath == relative }
            let record = AssetRecord(
                id: index.map { updated[$0].id } ?? UUID(),
                libraryID: library.id, filename: url.lastPathComponent, relativePath: relative,
                format: format, fileSizeBytes: Int64(values.fileSize ?? 0), width: 0, height: 0,
                finderTags: tags, isRaw: format.isRaw,
                addedToDirectoryDate: index.flatMap { updated[$0].addedToDirectoryDate } ?? values.creationDate,
                contentModificationDate: values.contentModificationDate
            )
            if let index { updated[index] = record } else { updated.append(record) }
        }
        return WorkspaceSnapshot(libraries: previous.libraries, assets: sortAssets(updated),
            compareGroups: CompareGroupingService.buildGroups(libraries: previous.libraries, assets: updated),
            keepFolderPath: previous.keepFolderPath, rejectFolderPath: previous.rejectFolderPath)
    }

    private func resolveDirectoryURL(from rawPath: String) -> URL? {
        let expandedPath = NSString(string: rawPath).expandingTildeInPath
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: expandedPath, isDirectory: true)
    }

    private func scanAssetBatches(
        in root: URL,
        libraryID: UUID,
        onBatch: ([AssetRecord]) -> Void
    ) async throws {
        let batches = try untaggedAssetBatches(in: root, libraryID: libraryID)
        for batch in batches {
            try Task.checkCancellation()
            if readsFinderTags {
                onBatch(await assetsByReadingFinderTags(in: batch, root: root))
            } else {
                onBatch(batch)
            }
        }
    }

    private func untaggedAssetBatches(in root: URL, libraryID: UUID) throws -> [[AssetRecord]] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .addedToDirectoryDateKey,
                .creationDateKey,
                .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var batches: [[AssetRecord]] = []
        var batch: [AssetRecord] = []
        batch.reserveCapacity(assetBatchSize)

        for case let fileURL as URL in enumerator {
            // Check during directory enumeration too, not only after all paths
            // have been materialized into batches (especially important on NFS).
            try Task.checkCancellation()
            let values = try fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .addedToDirectoryDateKey,
                .creationDateKey,
                .contentModificationDateKey,
            ])
            guard values.isRegularFile == true else { continue }

            let format = AssetFormat.infer(from: fileURL)
            guard format != .unknown else { continue }

            let fileSizeBytes = Int64(values.fileSize ?? 0)
            let relativePath = relativePath(for: fileURL, under: root)
            batch.append(
                AssetRecord(
                    libraryID: libraryID,
                    filename: fileURL.lastPathComponent,
                    relativePath: relativePath,
                    format: format,
                    fileSizeBytes: fileSizeBytes,
                    width: 0,
                    height: 0,
                    finderTags: [],
                    isRaw: format.isRaw,
                    addedToDirectoryDate: values.addedToDirectoryDate
                        ?? values.creationDate
                        ?? values.contentModificationDate,
                    contentModificationDate: values.contentModificationDate
                )
            )

            if batch.count >= assetBatchSize {
                batches.append(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }

        if !batch.isEmpty {
            batches.append(batch)
        }

        return batches
    }

    private func assetsByReadingFinderTags(in assets: [AssetRecord], root: URL) async -> [AssetRecord] {
        guard !assets.isEmpty else { return assets }

        let service = finderTagService
        let maximumConcurrentReads = min(16, assets.count)

        return await withTaskGroup(of: (Int, [FinderTag]).self, returning: [AssetRecord].self) { group in
            var taggedAssets = assets
            var nextIndex = 0

            for index in 0..<maximumConcurrentReads {
                let asset = assets[index]
                let fileURL = root.appendingPathComponent(asset.relativePath)
                group.addTask {
                    (index, (try? service.readTags(at: fileURL)) ?? [])
                }
                nextIndex += 1
            }

            while let (index, tags) = await group.next() {
                taggedAssets[index].finderTags = tags

                if nextIndex < assets.count {
                    let indexToRead = nextIndex
                    let asset = assets[indexToRead]
                    let fileURL = root.appendingPathComponent(asset.relativePath)
                    group.addTask {
                        (indexToRead, (try? service.readTags(at: fileURL)) ?? [])
                    }
                    nextIndex += 1
                }
            }

            return taggedAssets
        }
    }

    private func makeLibraries(from resolvedRoots: [URL]) -> [LibraryFolder] {
        resolvedRoots.enumerated().map { index, root in
            LibraryFolder(
                displayName: root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent,
                path: normalizedPath(root),
                columnIndex: index
            )
        }
    }

    private func makeSnapshot(
        libraries: [LibraryFolder],
        assets unsortedAssets: [AssetRecord],
        resolvedRoots: [URL]
    ) -> WorkspaceSnapshot {
        let assets = sortAssets(unsortedAssets)
        let compareGroups = CompareGroupingService.buildGroups(libraries: libraries, assets: assets)
        let baseRoot = resolvedRoots.first

        return WorkspaceSnapshot(
            libraries: libraries,
            assets: assets,
            compareGroups: compareGroups,
            keepFolderPath: baseRoot.map { normalizedPath($0.appendingPathComponent(keepFolderName, isDirectory: true)) } ?? keepFolderName,
            rejectFolderPath: baseRoot.map { normalizedPath($0.appendingPathComponent(rejectFolderName, isDirectory: true)) } ?? rejectFolderName
        )
    }

    private func sortAssets(_ assets: [AssetRecord]) -> [AssetRecord] {
        AssetFilenameSortKey.sorted(assets, pathFirst: true)
    }

    private func relativePath(for fileURL: URL, under root: URL) -> String {
        let rootPath = normalizedPath(root.standardizedFileURL)
        let fullPath = normalizedPath(fileURL.standardizedFileURL)

        guard fullPath.hasPrefix(rootPath + "/") else {
            return fileURL.lastPathComponent
        }

        return String(fullPath.dropFirst(rootPath.count + 1))
    }

    private func normalizedPath(_ url: URL) -> String {
        let path = url.path
        guard path.count > 1 else { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
