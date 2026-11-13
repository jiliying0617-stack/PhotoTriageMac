import Foundation

public struct PersistedAssetDecision: Codable, Equatable, Sendable {
    public var ratingState: RatingState
    public var appTags: [AppTag]
    public var finderTags: [String]
    public var rotationDegrees: Int

    public init(
        ratingState: RatingState,
        appTags: [AppTag],
        finderTags: [String],
        rotationDegrees: Int = 0
    ) {
        self.ratingState = ratingState
        self.appTags = appTags
        self.finderTags = finderTags
        self.rotationDegrees = AssetRecord.normalizedRotationDegrees(rotationDegrees)
    }
}

public protocol AssetDecisionPersisting: Sendable {
    func loadDecisions() -> [String: PersistedAssetDecision]
    func saveDecisions(_ decisions: [String: PersistedAssetDecision])
    func clearDecisions()
    /// Finish queued writes before normal application termination.
    func flushPendingWrites()
}

public extension AssetDecisionPersisting {
    func flushPendingWrites() {}
}

public struct NoopAssetDecisionStore: AssetDecisionPersisting {
    public init() {}
    public func loadDecisions() -> [String: PersistedAssetDecision] { [:] }
    public func saveDecisions(_ decisions: [String: PersistedAssetDecision]) {}
    public func clearDecisions() {}
}

public final class JSONAssetDecisionStore: AssetDecisionPersisting, @unchecked Sendable {
    private enum PendingWrite {
        case save([String: PersistedAssetDecision])
        case clear
    }
    private let fileURL: URL
    private let lock = NSLock()
    private let writerQueue = DispatchQueue(label: "PhotoTriage.decisions", qos: .utility)
    private var latestDecisions: [String: PersistedAssetDecision]?
    private var pendingWrite: PendingWrite?
    private var isWriterScheduled = false

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            self.fileURL = supportURL
                .appendingPathComponent("PhotoTriageMac", isDirectory: true)
                .appendingPathComponent("asset-decisions.json")
        }
    }

    public func loadDecisions() -> [String: PersistedAssetDecision] {
        // A second AppState must immediately see the most recent in-memory edit,
        // even when its atomic disk write is still queued.
        if let latest = lock.withLock({ latestDecisions }) { return latest }
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: PersistedAssetDecision].self, from: data)) ?? [:]
    }

    public func saveDecisions(_ decisions: [String: PersistedAssetDecision]) {
        lock.lock()
        latestDecisions = decisions
        pendingWrite = .save(decisions)
        scheduleWriterWhileLocked()
        lock.unlock()
    }

    private func scheduleWriterWhileLocked() {
        if !isWriterScheduled {
            isWriterScheduled = true
            // Enqueue under the lock so flush cannot race ahead of scheduling.
            writerQueue.async { [self] in drainPendingWrites() }
        }
    }

    private func drainPendingWrites() {
        while true {
            let operation: PendingWrite? = lock.withLock {
                guard let next = pendingWrite else {
                    isWriterScheduled = false
                    return nil
                }
                pendingWrite = nil
                return next
            }
            guard let operation else { return }
            // Only one active snapshot and one newest pending snapshot are kept.
            // Rapid key presses never build an unbounded queue of full encodes.
            autoreleasepool {
                switch operation {
                case .save(let decisions): writeDecisions(decisions)
                case .clear: try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }
    }

    private func writeDecisions(_ decisions: [String: PersistedAssetDecision]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(decisions)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Persistence should never interrupt triage.
        }
    }

    public func clearDecisions() {
        lock.lock()
        latestDecisions = [:]
        pendingWrite = .clear
        // A queued older save must never resurrect decisions after clear.
        scheduleWriterWhileLocked()
        lock.unlock()
        flushPendingWrites()
    }

    public func flushPendingWrites() {
        writerQueue.sync {}
    }
}

public enum AssetDecisionKey {
    public static func make(libraryPath: String, asset: AssetRecord) -> String {
        [
            libraryPath,
            asset.relativePath
        ]
        .joined(separator: "|")
        .lowercased()
    }
}
