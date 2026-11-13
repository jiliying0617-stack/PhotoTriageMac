import Foundation

/// Exact byte rollback for a multi-file transaction (never an inverse re-encode).
struct FileMutationBackup {
    private let directory: URL
    private let copies: [(source: URL, backup: URL)]
    var recoveryDirectory: String { directory.path }

    init(urls: [URL]) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoTriageRollback-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var entries: [(URL, URL)] = []
        do {
            for (index, url) in urls.enumerated() where FileManager.default.fileExists(atPath: url.path) {
                let backup = directory.appendingPathComponent(String(index))
                try FileManager.default.copyItem(at: url, to: backup)
                entries.append((url, backup))
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        copies = entries
    }

    func restore() throws {
        for entry in copies {
            let staged = entry.source.deletingLastPathComponent().appendingPathComponent(".photo-triage-restore-\(UUID())")
            defer { try? FileManager.default.removeItem(at: staged) }
            try FileManager.default.copyItem(at: entry.backup, to: staged)
            if FileManager.default.fileExists(atPath: entry.source.path) {
                _ = try FileManager.default.replaceItemAt(entry.source, withItemAt: staged)
            } else {
                try FileManager.default.moveItem(at: staged, to: entry.source)
            }
        }
    }

    func discard() { try? FileManager.default.removeItem(at: directory) }
}
