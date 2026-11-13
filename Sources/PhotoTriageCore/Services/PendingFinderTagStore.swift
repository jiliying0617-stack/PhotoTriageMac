import Foundation

/// A local edit that still needs to be written to Finder metadata.
/// An empty `tags` array is a deliberate request to clear the file's tags.
public struct PendingFinderTagEdit: Codable, Equatable, Sendable {
    public var tags: [FinderTag]
    public var reason: String

    public init(tags: [FinderTag], reason: String) {
        self.tags = tags
        self.reason = reason
    }
}

public enum PendingFinderTagKey {
    /// Keep case intact: two paths may refer to different files on a case-sensitive volume.
    public static func make(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}

public protocol PendingFinderTagPersisting: Sendable {
    func load() throws -> [String: PendingFinderTagEdit]

    /// Merge changes without replacing unrelated pending edits. Updates win over removals
    /// when a key is present in both arguments.
    func apply(
        updates: [String: PendingFinderTagEdit],
        removingKeys: Set<String>
    ) throws
}

/// Saves only pending-edit metadata; it never reads or modifies the source image files.
public final class JSONPendingFinderTagStore: PendingFinderTagPersisting, @unchecked Sendable {
    // Also serialize different store instances in this process so that a read/merge/write
    // cannot overwrite another instance's updates to the same JSON file.
    private static let storageLock = NSLock()
    private let fileURL: URL

    public static var defaultFileURL: URL {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return supportDirectory
            .appendingPathComponent("PhotoTriageMac", isDirectory: true)
            .appendingPathComponent("pending-finder-tags.json")
    }

    public init(fileURL: URL? = nil) {
        self.fileURL = (fileURL ?? Self.defaultFileURL).standardizedFileURL
    }

    public func load() throws -> [String: PendingFinderTagEdit] {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }
        return try readFromDisk()
    }

    public func apply(
        updates: [String: PendingFinderTagEdit],
        removingKeys: Set<String>
    ) throws {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }

        // Re-read under the lock instead of trusting a cache. In particular, a damaged
        // existing file must throw before any attempt to overwrite it.
        var edits = try readFromDisk()
        for key in removingKeys {
            edits.removeValue(forKey: key)
        }
        edits.merge(updates) { _, updated in updated }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(edits)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // No in-memory state is committed before this succeeds. Atomic replacement
        // preserves the previous record if saving the new record fails.
        try data.write(to: fileURL, options: .atomic)
    }

    private func readFromDisk() throws -> [String: PendingFinderTagEdit] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where
            error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return [:]
        }
        return try JSONDecoder().decode([String: PendingFinderTagEdit].self, from: data)
    }
}

/// An explicitly non-durable store for previews and tests. Values last only as long
/// as this instance; callers must not report them as saved to disk.
public final class MemoryPendingFinderTagStore: PendingFinderTagPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var edits: [String: PendingFinderTagEdit]

    public init(initialEdits: [String: PendingFinderTagEdit] = [:]) {
        edits = initialEdits
    }

    public func load() throws -> [String: PendingFinderTagEdit] {
        lock.lock()
        defer { lock.unlock() }
        return edits
    }

    public func apply(
        updates: [String: PendingFinderTagEdit],
        removingKeys: Set<String>
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        for key in removingKeys {
            edits.removeValue(forKey: key)
        }
        edits.merge(updates) { _, updated in updated }
    }
}
