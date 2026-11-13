import Foundation
@testable import PhotoTriageCore
import Testing

struct FilenameMatchingServiceTests {
    @Test
    func comparisonKeysIgnoreOnlyTheLastShortNumericSuffix() {
        let cases = [
            "0V2A6875_3.PNG": "0v2a6875",
            "photo_12.jpg": "photo",
            "photo_0.jpg": "photo",
            "photo_99.jpg": "photo",
            "1 (3)(11)_2.png": "1 (3)(11)",
            "634_0_2.jpg": "634_0",
            "634_1_1.png": "634_1",
            "pexels_1390600.jpg": "pexels_1390600",
            "photo_123.jpg": "photo_123",
            "photo_final.jpg": "photo_final",
            "photo_1_edit.jpg": "photo_1_edit",
            "photo_.png": "photo_",
            "_1.png": "_1",
        ]
        for (filename, expected) in cases {
            #expect(AssetRecord.comparisonFilenameKey(for: filename) == expected)
        }
        #expect(AssetRecord.comparisonRelativePathKey(for: "Folder_1/Photo_12.PNG") == "folder_1/photo")
        #expect(AssetRecord.filenameKey(for: "Photo_12.PNG") == "photo_12")
    }

    @Test
    func screenshotNamesPairAcrossExtensionsAndPreserveSourceNames() {
        let source = asset("0V2A6875.jpg")
        let result = asset("0V2A6875_3.png")
        let matches = FilenameMatchingService.match(referenceRows: [[source]], targets: [result])
        #expect(matches[0]?.id == result.id)
        #expect(matches[0]?.filename == "0V2A6875_3.png")
        #expect(matches[0]?.filenameKey == "0v2a6875_3")
        #expect(FilenameMatchingService.match(referenceRows: [[result]], targets: [source])[0]?.id == source.id)
    }

    @Test
    func pairingNormalizesUnicodeAndEdgeWhitespaceOnlyForComparison() {
        let composed = asset("épreuve.jpg")
        let decomposed = asset("e\u{301}preuve .PNG")
        let matches = FilenameMatchingService.match(referenceRows: [[composed]], targets: [decomposed])
        #expect(matches[0]?.id == decomposed.id)
        #expect(composed.filenameKey == "épreuve")
        #expect(decomposed.filenameKey == "e\u{301}preuve ".lowercased())
    }

    @Test
    func matchingRelativePathsNormalizeFolderAndBasenameWithoutChangingStoredKeys() {
        let source = asset("épreuve.jpg", folder: "原图")
        let target = asset("e\u{301}preuve .PNG", folder: "原图")
        #expect(FilenameMatchingService.match(
            referenceRows: [[source]], targets: [target], useRelativePath: true
        )[0]?.id == target.id)
        #expect(source.relativePath == "原图/épreuve.jpg")
        #expect(target.relativePath == "原图/e\u{301}preuve .PNG")
    }

    @Test
    func exactNamesAreReservedBeforeSuffixFallbacks() {
        let base = asset("photo.jpg")
        let numbered = asset("photo_1.jpg")
        let exact = asset("photo_1.png")
        let fallback = asset("photo_2.png")
        let matches = FilenameMatchingService.match(referenceRows: [[base], [numbered]], targets: [exact, fallback])
        #expect(matches[0]?.id == fallback.id)
        #expect(matches[1]?.id == exact.id)
    }

    @Test
    func oneSidedSuffixSupportsOriginalNamesThatAlreadyContainNumbers() {
        let original = asset("634_0.jpg")
        let result = asset("634_0_2.png")
        #expect(FilenameMatchingService.match(referenceRows: [[original]], targets: [result])[0]?.id == result.id)
        #expect(FilenameMatchingService.match(referenceRows: [[result]], targets: [original])[0]?.id == original.id)
        #expect(FilenameMatchingService.match(
            referenceRows: [[asset("634_0_2.jpg")]], targets: [asset("634_1_1.png")]
        ).isEmpty)
    }

    @Test
    func targetIsNeverReusedAndAllRowAliasesParticipate() {
        let target = asset("photo_3.png")
        let first = asset("photo_1.jpg")
        let second = asset("photo_2.jpg")
        let matches = FilenameMatchingService.match(referenceRows: [[first], [second, target]], targets: [target])
        #expect(matches.count == 1)
        #expect(matches[0] == nil)
        #expect(matches[1]?.id == target.id)
    }

    @Test
    func relativePathMatchingDoesNotStripFolderSuffixes() {
        let source = asset("photo.jpg", folder: "set_1")
        let right = asset("photo_2.png", folder: "set_1")
        let wrong = asset("photo_2.png", folder: "set_2")
        #expect(FilenameMatchingService.match(
            referenceRows: [[source]], targets: [wrong, right], useRelativePath: true
        )[0]?.id == right.id)
    }

    @Test
    func sortingKeepsSameStemVariantsTogetherWithDeterministicTies() {
        let assets = ["b.jpg", "a-variant.jpg", "a_12.png", "a.jpg", "a_2.png"].map { asset($0) }
        let sorted = AssetFilenameSortKey.sorted(assets)
        #expect(Set(sorted.prefix(3).map(\.filename)) == ["a.jpg", "a_2.png", "a_12.png"])
        #expect(sorted.suffix(2).map(\.filename) == ["a-variant.jpg", "b.jpg"])
        #expect(AssetFilenameSortKey.sorted(Array(assets.reversed())).map(\.id) == sorted.map(\.id))
        let snapshot = VisibleAssetSnapshot(assets: assets)
        #expect(snapshot.assetIDs == sorted.map(\.id))
        #expect(snapshot.filenameSequentialCompareGroups(batchSize: 3).first?.map(\.id) == Array(sorted.prefix(3)).map(\.id))
    }

    @Test
    func numericExportSuffixesFollowTheirBaseFile() {
        let assets = [
            "00408(1)_3.png", "00408(1).jpg", "00408(1)_12.png", "00408(1)_2.png",
            "00407.jpg", "00409.jpg"
        ].map { asset($0) }
        let sorted = AssetFilenameSortKey.sorted(assets).map(\.filename)
        #expect(sorted.drop(while: { $0 != "00408(1).jpg" }).prefix(4) == [
            "00408(1).jpg", "00408(1)_2.png", "00408(1)_3.png", "00408(1)_12.png"
        ])
        #expect(AssetRecord.comparisonFilenameSequence(for: "00408(1).jpg") == nil)
        #expect(AssetRecord.comparisonFilenameSequence(for: "00408(1)_2.png") == 2)
    }

    @Test
    func libraryGroupsPreserveDuplicatesAndMissingSlots() {
        let libraries = [
            LibraryFolder(displayName: "A", path: "/tmp/A", columnIndex: 0),
            LibraryFolder(displayName: "B", path: "/tmp/B", columnIndex: 1),
        ]
        let assets = [
            asset("photo.jpg", libraryID: libraries[0].id),
            asset("photo.png", libraryID: libraries[0].id),
            asset("photo_1.png", libraryID: libraries[1].id),
        ]
        let groups = CompareGroupingService.buildGroups(libraries: libraries, assets: assets)
        #expect(groups.count == 2)
        #expect(Set(groups.map(\.id)).count == 2)
        #expect(groups.flatMap { $0.slots.compactMap { $0.asset?.id } }.count == 3)
        #expect(groups.filter { $0.slots[1].asset == nil }.count == 1)
    }

    @Test
    func pairsTwentyThousandRecordsWithoutLosingOrReusingTargets() {
        let sources = (0..<10_000).map { asset("image\($0).jpg") }
        let targets = (0..<10_000).reversed().map { asset("image\($0)_12.png") }
        let clock = ContinuousClock()
        let start = clock.now
        let matches = FilenameMatchingService.match(referenceRows: sources.map { [$0] }, targets: targets)
        print("20,000-record filename pairing: \(start.duration(to: clock.now))")
        #expect(matches.count == 10_000)
        #expect(Set(matches.values.map(\.id)).count == 10_000)
        #expect(sources.indices.allSatisfy { matches[$0]?.filename == "image\($0)_12.png" })
    }

    private func asset(_ filename: String, folder: String? = nil, libraryID: UUID = UUID()) -> AssetRecord {
        AssetRecord(
            libraryID: libraryID, filename: filename,
            relativePath: folder.map { $0 + "/" + filename } ?? filename,
            format: filename.lowercased().hasSuffix(".png") ? .png : .jpg,
            fileSizeBytes: 100, width: 100, height: 100
        )
    }
}
