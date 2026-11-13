import Foundation

public struct FileSystemExportService: ExportExecuting {
    private let planner: any ExportPlanning
    private let synchronizesFinderTags: Bool
    public init(planner: any ExportPlanning = ExportPlanner(), synchronizesFinderTags: Bool = true) {
        self.planner = planner
        self.synchronizesFinderTags = synchronizesFinderTags
    }

    public func export(_ request: ExportRequest) async throws -> ExportExecutionSummary {
        let buckets = planner.buildExportBuckets(from: request.assets, includePending: request.includePending)
        let task = Task.detached(priority: .userInitiated) {
            await ExportFileWorker.shared.execute(request, buckets: buckets, synchronizesFinderTags: synchronizesFinderTags)
        }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}

/// Serializes destination allocation across exports. Files already copied identically are safe to retry.
private actor ExportFileWorker {
    static let shared = ExportFileWorker()
    private struct Item {
        let asset: AssetRecord
        let root: String
        let rating: RatingState?
        let priority: PriorityTag?
        let color: FinderTagColor?
    }
    private struct Receipt: Codable {
        let source: String
        let destination: String
        let status: String
        let detail: String?
    }

    func execute(_ request: ExportRequest, buckets: [RatingState: [AssetRecord]], synchronizesFinderTags: Bool) -> ExportExecutionSummary {
        var items: [Item] = []
        for (enabled, rating, root) in [
            (request.includeKeep, RatingState.keep, request.keepFolderPath),
            (request.includeReject, .reject, request.rejectFolderPath),
            (request.includePending, .pending, request.pendingFolderPath)
        ] where enabled {
            items += (buckets[rating] ?? []).map { Item(asset: $0, root: root, rating: rating, priority: nil, color: nil) }
        }
        for tag in request.includedPriorityTags.sorted() {
            guard let root = request.priorityTagFolderPaths[tag] else { continue }
            items += request.assets.filter { $0.priorityTag == tag }.map { Item(asset: $0, root: root, rating: nil, priority: tag, color: nil) }
        }
        for color in FinderTagColor.visibleColors where synchronizesFinderTags && request.includedFinderTagColors.contains(color) {
            guard let root = request.finderTagFolderPaths[color] else { continue }
            items += request.assets.filter { $0.finderTags.contains { $0.color == color } }
                .map { Item(asset: $0, root: root, rating: nil, priority: nil, color: color) }
        }
        var summary = ExportExecutionSummary(exportedCount: 0, keepCount: 0, rejectCount: 0, pendingCount: 0)
        var receipts: [Receipt] = []
        let libraries = Dictionary(uniqueKeysWithValues: request.libraries.map { ($0.id, $0) })
        request.onProgress?(ExportProgress(completed: 0, total: items.count))
        for (index, item) in items.enumerated() {
            if Task.isCancelled { summary.wasCancelled = true; break }
            let source = libraries[item.asset.libraryID].map {
                URL(fileURLWithPath: $0.path).appendingPathComponent(item.asset.relativePath)
            }
            do {
                guard let source else { throw ExportExecutionError.missingLibrary(item.asset.libraryID) }
                guard FileManager.default.fileExists(atPath: source.path) else {
                    throw ExportExecutionError.missingSourceAsset(source.path)
                }
                let root = URL(fileURLWithPath: item.root, isDirectory: true).standardizedFileURL
                let proposed = root.appendingPathComponent(item.asset.relativePath).standardizedFileURL
                guard !item.root.isEmpty, proposed.path.hasPrefix(root.path + "/") else {
                    throw CocoaError(.fileWriteInvalidFileName)
                }
                try FileManager.default.createDirectory(at: proposed.deletingLastPathComponent(), withIntermediateDirectories: true)
                let hasPendingTags = synchronizesFinderTags && item.asset.finderTagSyncIssue != nil
                let (destination, existing) = try destination(
                    for: proposed,
                    source: source,
                    requiresIndependentCopy: hasPendingTags
                )
                if existing {
                    // Synchronize tags too: file contents can stay identical while Finder tags change.
                    if synchronizesFinderTags, try !refersToSameFile(source, destination) {
                        let tags = hasPendingTags
                            ? item.asset.finderTags
                            : try FileSystemFinderTagService().readTags(at: source)
                        if hasPendingTags {
                            try writePendingTags(tags, toExportCopy: destination)
                        } else {
                            try FileSystemFinderTagService().writeTags(tags, at: destination)
                        }
                    }
                    summary.skippedCount += 1
                } else {
                    let staged = destination.deletingLastPathComponent().appendingPathComponent(".photo-triage-export-\(UUID())")
                    defer { try? FileManager.default.removeItem(at: staged) }
                    // A copied symbolic link still points to the original. Materialize the
                    // file before applying a local-only edit so exporting cannot tag the source.
                    let copySource = hasPendingTags ? source.resolvingSymlinksInPath() : source
                    try FileManager.default.copyItem(at: copySource, to: staged)
                    if hasPendingTags {
                        try writePendingTags(item.asset.finderTags, toExportCopy: staged)
                    }
                    try Task.checkCancellation()
                    try FileManager.default.moveItem(at: staged, to: destination)
                    summary.exportedCount += 1
                    if destination != proposed { summary.renamedConflictCount += 1 }
                }
                switch item.rating {
                case .keep: summary.keepCount += 1
                case .reject: summary.rejectCount += 1
                case .pending: summary.pendingCount += 1
                case nil: break
                }
                summary.priorityTagSummary.record(item.priority)
                if let color = item.color { summary.finderTagColorSummary.counts[color, default: 0] += 1 }
                receipts.append(Receipt(source: source.path, destination: destination.path, status: existing ? "已存在，跳过复制" : "成功", detail: nil))
            } catch is CancellationError {
                summary.wasCancelled = true
                break
            } catch {
                let path = source?.path ?? item.asset.relativePath
                summary.failures.append(ExportFailure(sourcePath: path, message: error.localizedDescription))
                receipts.append(Receipt(source: path, destination: item.root, status: "失败", detail: error.localizedDescription))
            }
            if index % 10 == 0 || index + 1 == items.count {
                request.onProgress?(ExportProgress(completed: index + 1, total: items.count))
            }
        }
        if let root = items.first?.root, !root.isEmpty {
            let receiptURL = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(".筛图导出记录-\(UUID()).json")
            do {
                try FileManager.default.createDirectory(at: receiptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(receipts).write(to: receiptURL, options: .atomic)
                summary.receiptPath = receiptURL.path
            } catch {
                summary.failures.append(ExportFailure(sourcePath: receiptURL.path, message: "导出清单保存失败：\(error.localizedDescription)"))
            }
        }
        return summary
    }

    private func destination(
        for proposed: URL,
        source: URL,
        requiresIndependentCopy: Bool
    ) throws -> (URL, Bool) {
        var candidate = proposed
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            if FileManager.default.contentsEqual(atPath: source.path, andPath: candidate.path) {
                let isSymbolicLink = try candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
                // Pending tags belong to the export copy, never to a source file or
                // another file reached through a link in the destination directory.
                if !isSymbolicLink {
                    if !requiresIndependentCopy { return (candidate, true) }
                    if try !refersToSameFile(source, candidate) { return (candidate, true) }
                } else if !requiresIndependentCopy {
                    // A normal copied source link needs no metadata changes and
                    // remains idempotent when the export is repeated.
                    if try refersToSameFile(source, candidate) { return (candidate, true) }
                }
            }
            let stem = proposed.deletingPathExtension().lastPathComponent
            let ext = proposed.pathExtension
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            candidate = proposed.deletingLastPathComponent().appendingPathComponent(name)
            index += 1
        }
        return (candidate, false)
    }

    private func refersToSameFile(_ first: URL, _ second: URL) throws -> Bool {
        let firstResolved = first.standardizedFileURL.resolvingSymlinksInPath()
        let secondResolved = second.standardizedFileURL.resolvingSymlinksInPath()
        if firstResolved == secondResolved { return true }
        let firstAttributes = try FileManager.default.attributesOfItem(atPath: firstResolved.path)
        let secondAttributes = try FileManager.default.attributesOfItem(atPath: secondResolved.path)
        guard let firstDevice = firstAttributes[.systemNumber] as? NSNumber,
              let secondDevice = secondAttributes[.systemNumber] as? NSNumber,
              let firstFile = firstAttributes[.systemFileNumber] as? NSNumber,
              let secondFile = secondAttributes[.systemFileNumber] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        return firstDevice == secondDevice && firstFile == secondFile
    }

    private func writePendingTags(_ tags: [FinderTag], toExportCopy url: URL) throws {
        // Copies inherit the source's read-only mode. Temporarily allow metadata
        // writes on this independent export copy, then restore its original mode.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue else {
            throw CocoaError(.fileReadUnknown)
        }
        let needsWritePermission = permissions & 0o200 == 0
        if needsWritePermission {
            try FileManager.default.setAttributes([.posixPermissions: permissions | 0o200], ofItemAtPath: url.path)
        }
        do {
            try FileSystemFinderTagService().writeTags(tags, at: url)
        } catch {
            if needsWritePermission {
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
            }
            throw error
        }
        if needsWritePermission {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }
}
