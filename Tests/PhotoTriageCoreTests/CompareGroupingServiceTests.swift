import PhotoTriageCore
import Testing

struct CompareGroupingServiceTests {
    @Test
    func buildsFixedSlotsForEveryLibrary() {
        let libraries = [
            LibraryFolder(displayName: "A", path: "/A", columnIndex: 0),
            LibraryFolder(displayName: "B", path: "/B", columnIndex: 1),
            LibraryFolder(displayName: "C", path: "/C", columnIndex: 2),
        ]

        let assets = [
            AssetRecord(
                libraryID: libraries[0].id,
                filename: "sample.jpg",
                relativePath: "sample.jpg",
                format: .jpg,
                fileSizeBytes: 100,
                width: 100,
                height: 100
            ),
            AssetRecord(
                libraryID: libraries[2].id,
                filename: "sample.jpg",
                relativePath: "sample.jpg",
                format: .jpg,
                fileSizeBytes: 100,
                width: 100,
                height: 100
            ),
        ]

        let groups = CompareGroupingService.buildGroups(libraries: libraries, assets: assets)

        #expect(groups.count == 1)
        #expect(groups[0].relativePath == "sample")
        #expect(groups[0].slots.count == 3)
        #expect(groups[0].slots[1].asset == nil)
        #expect(groups[0].slots[0].asset?.filename == "sample.jpg")
        #expect(groups[0].slots[2].asset?.filename == "sample.jpg")
    }

    @Test
    func matchesRelativePathsByNameWithoutRequiringSameExtension() {
        let libraries = [
            LibraryFolder(displayName: "A", path: "/A", columnIndex: 0),
            LibraryFolder(displayName: "B", path: "/B", columnIndex: 1),
        ]

        let assets = [
            AssetRecord(
                libraryID: libraries[0].id,
                filename: "sample.jpg",
                relativePath: "set-a/sample.jpg",
                format: .jpg,
                fileSizeBytes: 100,
                width: 100,
                height: 100
            ),
            AssetRecord(
                libraryID: libraries[1].id,
                filename: "sample.png",
                relativePath: "set-a/sample.png",
                format: .png,
                fileSizeBytes: 100,
                width: 100,
                height: 100
            ),
            AssetRecord(
                libraryID: libraries[0].id,
                filename: "sample.jpg",
                relativePath: "set-b/sample.jpg",
                format: .jpg,
                fileSizeBytes: 100,
                width: 100,
                height: 100
            ),
        ]

        let groups = CompareGroupingService.buildGroups(libraries: libraries, assets: assets)

        #expect(groups.count == 2)
        #expect(groups.map(\.relativePath) == ["set-a/sample", "set-b/sample"])
        #expect(groups[0].slots[0].asset?.relativePath == "set-a/sample.jpg")
        #expect(groups[0].slots[1].asset?.relativePath == "set-a/sample.png")
        #expect(groups[1].slots[0].asset?.relativePath == "set-b/sample.jpg")
        #expect(groups[1].slots[1].asset == nil)
    }

    @Test
    func suffixOnlyRowsAreOrderedImmediatelyAfterTheirBaseGroup() {
        let libraries = [
            LibraryFolder(displayName: "A", path: "/A", columnIndex: 0),
            LibraryFolder(displayName: "B", path: "/B", columnIndex: 1),
        ]
        let assets = [
            AssetRecord(libraryID: libraries[0].id, filename: "001.jpg", relativePath: "001.jpg", format: .jpg, fileSizeBytes: 100, width: 1, height: 1),
            AssetRecord(libraryID: libraries[0].id, filename: "003.jpg", relativePath: "003.jpg", format: .jpg, fileSizeBytes: 100, width: 1, height: 1),
            AssetRecord(libraryID: libraries[1].id, filename: "001.jpg", relativePath: "001.jpg", format: .jpg, fileSizeBytes: 100, width: 1, height: 1),
            AssetRecord(libraryID: libraries[1].id, filename: "001_2.jpg", relativePath: "001_2.jpg", format: .jpg, fileSizeBytes: 100, width: 1, height: 1),
            AssetRecord(libraryID: libraries[1].id, filename: "001_3.jpg", relativePath: "001_3.jpg", format: .jpg, fileSizeBytes: 100, width: 1, height: 1),
            AssetRecord(libraryID: libraries[1].id, filename: "003.jpg", relativePath: "003.jpg", format: .jpg, fileSizeBytes: 100, width: 1, height: 1),
        ]

        let groups = CompareGroupingService.buildGroups(libraries: libraries, assets: assets)

        #expect(groups.map { $0.slots.map { $0.asset?.filename } } == [
            ["001.jpg", "001.jpg"],
            [nil, "001_2.jpg"],
            [nil, "001_3.jpg"],
            ["003.jpg", "003.jpg"],
        ])
    }

    @Test
    func differentNamesStayInSeparateCompareGroups() {
        let libraries = [
            LibraryFolder(displayName: "A", path: "/A", columnIndex: 0),
            LibraryFolder(displayName: "B", path: "/B", columnIndex: 1),
        ]
        let assets = [
            AssetRecord(
                libraryID: libraries[0].id,
                filename: "first.jpg",
                relativePath: "first.jpg",
                format: .jpg,
                fileSizeBytes: 10_000,
                width: 100,
                height: 100,
            ),
            AssetRecord(
                libraryID: libraries[1].id,
                filename: "renamed-output.jpg",
                relativePath: "renamed-output.jpg",
                format: .jpg,
                fileSizeBytes: 10_050,
                width: 100,
                height: 100
            ),
        ]

        let groups = CompareGroupingService.buildGroups(libraries: libraries, assets: assets)

        #expect(groups.count == 2)
        #expect(groups.contains { group in
            group.slots[0].asset?.filename == "first.jpg" && group.slots[1].asset == nil
        })
        #expect(groups.contains { group in
            group.slots[0].asset == nil && group.slots[1].asset?.filename == "renamed-output.jpg"
        })
    }
}
