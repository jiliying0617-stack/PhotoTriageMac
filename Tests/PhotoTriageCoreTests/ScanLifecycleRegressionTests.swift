import Foundation
@testable import PhotoTriageCore
import Testing

struct ScanLifecycleRegressionTests {
    @Test
    func slowSnapshotConsumerRetainsOnlyNewestCompleteState() async throws {
        let finished = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let snapshots = WorkspaceSnapshotStream.make { continuation in
            for index in 0..<500 {
                continuation.yield(WorkspaceSnapshot(libraries: [], assets: [], compareGroups: [],
                    keepFolderPath: "snapshot-\(index)", rejectFolderPath: ""))
            }
            finished.continuation.yield(())
            finished.continuation.finish()
        }
        // Do not consume until all cumulative snapshots have been produced.
        for await _ in finished.stream {}
        var paths: [String] = []
        for try await snapshot in snapshots { paths.append(snapshot.keepFolderPath) }
        #expect(paths == ["snapshot-499"])
    }

    @Test(.timeLimit(.minutes(1)))
    func canceledSnapshotConsumerCancelsItsProducer() async throws {
        let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let stopped = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let snapshots = WorkspaceSnapshotStream.make { continuation in
            continuation.yield(WorkspaceSnapshot(libraries: [], assets: [], compareGroups: [], keepFolderPath: "", rejectFolderPath: ""))
            started.continuation.yield(())
            started.continuation.finish()
            do {
                try await Task.sleep(for: .seconds(30))
                stopped.continuation.yield(false)
            } catch is CancellationError {
                stopped.continuation.yield(true)
            }
            stopped.continuation.finish()
        }
        let consumer = Task {
            do { for try await _ in snapshots {} } catch {}
        }
        for await _ in started.stream {}
        consumer.cancel()
        await consumer.value
        var canceled = false
        for await value in stopped.stream { canceled = value }
        #expect(canceled)
    }

    @Test
    func watcherConcurrentStartStopReleasesOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        weak var observed: WorkspaceFileWatcher?
        do {
            let watcher = WorkspaceFileWatcher(rootPaths: [root.path], onChange: {})
            observed = watcher
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<20 {
                    group.addTask { watcher.start(); watcher.stop() }
                }
            }
            watcher.start()
            watcher.stop()
        }
        #expect(observed == nil)
    }
}
