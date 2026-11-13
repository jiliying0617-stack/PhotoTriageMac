import Foundation
import PhotoTriageCore
import Testing

struct PendingFinderTagStoreTests {
    @Test
    func missingRecordLoadsAsEmptyWithoutCreatingAFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recordURL = root.appendingPathComponent("nested/pending.json")

        #expect(try JSONPendingFinderTagStore(fileURL: recordURL).load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: recordURL.path))
    }

    @Test
    func savedEditsSurviveCreatingANewStore() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recordURL = root.appendingPathComponent("support/pending.json")
        let key = PendingFinderTagKey.make(for: root.appendingPathComponent("照片.jpg"))
        let expected = PendingFinderTagEdit(
            tags: [FinderTag(name: "精选", color: .red), FinderTag(name: "客户", color: .blue)],
            reason: "文件暂时无法写入"
        )

        try JSONPendingFinderTagStore(fileURL: recordURL).apply(
            updates: [key: expected], removingKeys: []
        )

        #expect(try JSONPendingFinderTagStore(fileURL: recordURL).load() == [key: expected])
    }

    @Test
    func emptyTagsPersistAsAClearTombstoneUntilExplicitlyRemoved() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recordURL = root.appendingPathComponent("pending.json")
        let store = JSONPendingFinderTagStore(fileURL: recordURL)
        let key = PendingFinderTagKey.make(for: root.appendingPathComponent("clear.jpg"))
        let tombstone = PendingFinderTagEdit(tags: [], reason: "等待清除 Finder 标签")

        try store.apply(updates: [key: tombstone], removingKeys: [])
        #expect(try JSONPendingFinderTagStore(fileURL: recordURL).load()[key] == tombstone)

        try store.apply(updates: [:], removingKeys: [key])
        #expect(try JSONPendingFinderTagStore(fileURL: recordURL).load().isEmpty)
    }

    @Test
    func mergesUpdatesAndRemovalsWithoutDroppingOtherPaths() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recordURL = root.appendingPathComponent("pending.json")
        let first = JSONPendingFinderTagStore(fileURL: recordURL)
        let second = JSONPendingFinderTagStore(fileURL: recordURL)
        let firstKey = PendingFinderTagKey.make(for: root.appendingPathComponent("album-a/same.jpg"))
        let secondKey = PendingFinderTagKey.make(for: root.appendingPathComponent("album-b/same.jpg"))
        let removedKey = PendingFinderTagKey.make(for: root.appendingPathComponent("old.jpg"))
        let red = makeEdit(color: .red)
        let blue = makeEdit(color: .blue)

        #expect(try second.load().isEmpty)
        try first.apply(updates: [firstKey: red, removedKey: red], removingKeys: [])
        try second.apply(updates: [secondKey: blue], removingKeys: [removedKey])

        #expect(try first.load() == [firstKey: red, secondKey: blue])
    }

    @Test
    func concurrentStoresMergeEveryEdit() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recordURL = root.appendingPathComponent("pending.json")
        let stores = [
            JSONPendingFinderTagStore(fileURL: recordURL),
            JSONPendingFinderTagStore(fileURL: recordURL),
        ]

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    let key = PendingFinderTagKey.make(
                        for: root.appendingPathComponent("album-\(index)/same.jpg")
                    )
                    try stores[index % stores.count].apply(
                        updates: [key: PendingFinderTagEdit(tags: [], reason: "edit-\(index)")],
                        removingKeys: []
                    )
                }
            }
            try await group.waitForAll()
        }

        let edits = try JSONPendingFinderTagStore(fileURL: recordURL).load()
        #expect(edits.count == 40)
        for index in 0..<40 {
            let key = PendingFinderTagKey.make(for: root.appendingPathComponent("album-\(index)/same.jpg"))
            #expect(edits[key]?.reason == "edit-\(index)")
        }
    }

    @Test
    func keysStandardizePathsWithoutFoldingCase() {
        let upper = URL(fileURLWithPath: "/Volumes/Photos/Album/IMG.JPG")
        let lower = URL(fileURLWithPath: "/Volumes/Photos/Album/img.jpg")
        let equivalent = URL(fileURLWithPath: "/Volumes/Photos/Album/../Album/IMG.JPG")

        #expect(PendingFinderTagKey.make(for: upper) == upper.standardizedFileURL.path)
        #expect(PendingFinderTagKey.make(for: upper) == PendingFinderTagKey.make(for: equivalent))
        #expect(PendingFinderTagKey.make(for: upper) != PendingFinderTagKey.make(for: lower))
        #expect(PendingFinderTagKey.make(for: upper).hasSuffix("/IMG.JPG"))
    }

    @Test
    func persistingEditsDoesNotChangeTheOriginalFileOrItsFinderTags() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let imageURL = root.appendingPathComponent("original.jpg")
        let original = Data("original-image-bytes".utf8)
        try original.write(to: imageURL)
        let finderTags = FileSystemFinderTagService()
        let originalTags = [FinderTag(name: "原标签", color: .green)]
        try finderTags.writeTags(originalTags, at: imageURL)
        let originalDate = try imageURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        let key = PendingFinderTagKey.make(for: imageURL)
        let store = JSONPendingFinderTagStore(fileURL: root.appendingPathComponent("support/pending.json"))

        try store.apply(updates: [key: makeEdit(color: .red)], removingKeys: [])
        try store.apply(updates: [key: PendingFinderTagEdit(tags: [], reason: "clear")], removingKeys: [])

        #expect(try Data(contentsOf: imageURL) == original)
        #expect(try finderTags.readTags(at: imageURL) == originalTags)
        #expect(try imageURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate == originalDate)
    }

    @Test
    func damagedRecordThrowsAndIsNeverOverwrittenEvenAfterAPreviousLoad() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recordURL = root.appendingPathComponent("pending.json")
        let store = JSONPendingFinderTagStore(fileURL: recordURL)
        try store.apply(updates: ["/original.jpg": makeEdit(color: .red)], removingKeys: [])
        #expect(try store.load().count == 1)
        let damagedRecord = Data("{ damaged record".utf8)
        try damagedRecord.write(to: recordURL)

        #expect(throws: DecodingError.self) { try store.load() }
        #expect(throws: DecodingError.self) {
            try store.apply(updates: ["/new.jpg": makeEdit(color: .blue)], removingKeys: [])
        }
        #expect(try Data(contentsOf: recordURL) == damagedRecord)
    }

    @Test
    func invalidStorageDestinationThrowsWithoutReplacingTheBlockingFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let blockingURL = root.appendingPathComponent("not-a-directory")
        let original = Data("do-not-overwrite".utf8)
        try original.write(to: blockingURL)
        let recordURL = blockingURL.appendingPathComponent("pending.json")
        let store = JSONPendingFinderTagStore(fileURL: recordURL)

        #expect(throws: (any Error).self) {
            try store.apply(updates: ["/new.jpg": makeEdit(color: .red)], removingKeys: [])
        }
        #expect(try Data(contentsOf: blockingURL) == original)

        // Once the destination is usable, a failed edit must not appear as committed.
        try FileManager.default.removeItem(at: blockingURL)
        try FileManager.default.createDirectory(at: blockingURL, withIntermediateDirectories: true)
        #expect(try store.load().isEmpty)
    }

    @Test
    func memoryStoreMergesClearsAndDoesNotShareStateWithNewInstances() throws {
        let red = makeEdit(color: .red)
        let blue = makeEdit(color: .blue)
        let tombstone = PendingFinderTagEdit(tags: [], reason: "clear")
        let store = MemoryPendingFinderTagStore(initialEdits: ["/first.jpg": red, "/old.jpg": red])

        try store.apply(updates: ["/second.jpg": blue], removingKeys: ["/old.jpg"])
        try store.apply(updates: ["/first.jpg": tombstone], removingKeys: [])

        #expect(try store.load() == ["/first.jpg": tombstone, "/second.jpg": blue])
        #expect(try MemoryPendingFinderTagStore().load().isEmpty)
    }

    @Test
    func memoryStoreSerializesConcurrentUpdates() async throws {
        let store = MemoryPendingFinderTagStore()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    try store.apply(
                        updates: ["/\(index).jpg": PendingFinderTagEdit(tags: [], reason: "clear")],
                        removingKeys: []
                    )
                }
            }
            try await group.waitForAll()
        }
        #expect(try store.load().count == 100)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoTriagePendingFinderTags-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeEdit(color: FinderTagColor) -> PendingFinderTagEdit {
        PendingFinderTagEdit(tags: [FinderTag(name: color.displayName, color: color)], reason: "等待写入")
    }
}
