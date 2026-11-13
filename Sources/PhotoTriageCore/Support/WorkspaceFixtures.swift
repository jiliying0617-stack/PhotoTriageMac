import Foundation

enum WorkspaceFixtures {
    static func makeAssets(libraries: [LibraryFolder]) -> [AssetRecord] {
        guard libraries.count >= 3 else { return [] }

        let originals = libraries[0]
        let retouched = libraries[1]
        let delivery = libraries[2]

        return [
            AssetRecord(
                libraryID: originals.id,
                filename: "look-001.CR2",
                relativePath: "set-a/look-001.CR2",
                format: .cr2,
                fileSizeBytes: 42_000_000,
                width: 6240,
                height: 4160,
                ratingState: .pending,
                appTags: [AppTag(name: "人像")],
                finderTags: ["人像"],
                isRaw: true
            ),
            AssetRecord(
                libraryID: retouched.id,
                filename: "look-001.CR2",
                relativePath: "set-a/look-001.CR2",
                format: .cr2,
                fileSizeBytes: 42_000_000,
                width: 6240,
                height: 4160,
                ratingState: .keep,
                appTags: [AppTag(name: "已修")],
                finderTags: ["已修"],
                isRaw: true
            ),
            AssetRecord(
                libraryID: delivery.id,
                filename: "look-001.CR2",
                relativePath: "set-a/look-001.CR2",
                format: .cr2,
                fileSizeBytes: 42_000_000,
                width: 6240,
                height: 4160,
                ratingState: .keep,
                appTags: [AppTag(name: "交付")],
                finderTags: ["交付"],
                isRaw: true
            ),
            AssetRecord(
                libraryID: originals.id,
                filename: "look-002.HEIC",
                relativePath: "set-a/look-002.HEIC",
                format: .heic,
                fileSizeBytes: 8_200_000,
                width: 4032,
                height: 3024,
                ratingState: .pending,
                appTags: [AppTag(name: "待选")],
                finderTags: ["待选"]
            ),
            AssetRecord(
                libraryID: retouched.id,
                filename: "look-002.HEIC",
                relativePath: "set-a/look-002.HEIC",
                format: .heic,
                fileSizeBytes: 8_200_000,
                width: 4032,
                height: 3024,
                ratingState: .reject,
                appTags: [AppTag(name: "偏色")],
                finderTags: ["偏色"]
            ),
            AssetRecord(
                libraryID: originals.id,
                filename: "campaign-011.JPG",
                relativePath: "set-b/campaign-011.JPG",
                format: .jpg,
                fileSizeBytes: 5_400_000,
                width: 3000,
                height: 2000,
                ratingState: .pending,
                appTags: [AppTag(name: "封面候选")],
                finderTags: ["封面候选"]
            ),
            AssetRecord(
                libraryID: delivery.id,
                filename: "campaign-011.JPG",
                relativePath: "set-b/campaign-011.JPG",
                format: .jpg,
                fileSizeBytes: 5_100_000,
                width: 3000,
                height: 2000,
                ratingState: .keep,
                appTags: [AppTag(name: "已交付")],
                finderTags: ["已交付"]
            ),
            AssetRecord(
                libraryID: originals.id,
                filename: "web-banner-04.webp",
                relativePath: "exports/web-banner-04.webp",
                format: .webp,
                fileSizeBytes: 920_000,
                width: 1600,
                height: 900,
                ratingState: .pending,
                appTags: [AppTag(name: "Web")],
                finderTags: ["Web"]
            ),
            AssetRecord(
                libraryID: retouched.id,
                filename: "web-banner-04.webp",
                relativePath: "exports/web-banner-04.webp",
                format: .webp,
                fileSizeBytes: 890_000,
                width: 1600,
                height: 900,
                ratingState: .keep,
                appTags: [AppTag(name: "Web")],
                finderTags: ["Web"]
            ),
        ]
    }
}
