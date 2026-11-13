import Foundation
import Testing
@testable import PhotoTriageCore

struct CompareRowInsertionServiceTests {
    @Test
    func variantsAfterEarlierAddedDateRowStayAheadOfNextRowsEarlierVariants() {
        // Added-date ordering need not be alphabetical. Both new variants land
        // at boundary 1, but B_2 belongs to the preceding B row, not after A_2.
        let b = asset("B_1.png", folder: "reference")
        let a = asset("A_3.png", folder: "reference")
        let rows: [[AssetRecord?]] = [
            [b, asset("B_1.png", folder: "result")],
            [a, asset("A_3.png", folder: "result")],
        ]
        let b2 = asset("B_2.png", folder: "result")
        let a2 = asset("A_2.png", folder: "result")

        let result = CompareRowInsertionService.inserting(
            [a2, b2], into: rows, column: 1, columnCount: 2
        )

        #expect(result.map { $0.map { $0?.filename } } == [
            ["B_1.png", "B_1.png"],
            [nil, "B_2.png"],
            [nil, "A_2.png"],
            ["A_3.png", "A_3.png"],
        ])
        #expect(result.compactMap { $0[0]?.id } == [b.id, a.id])
    }

    @Test
    func severalLaterVariantsStayContiguousAcrossSameInsertionBoundary() {
        let rows: [[AssetRecord?]] = [
            [asset("B_1.png", folder: "reference"), asset("B_1.png", folder: "result"), nil],
            [asset("A_10.png", folder: "reference"), asset("A_10.png", folder: "result"), nil],
        ]
        let targets = ["A_2.png", "B_10.png", "A_3.png", "B_3.png", "B_2.png"]
            .map { asset($0, folder: "third") }

        let result = CompareRowInsertionService.inserting(
            targets, into: rows, column: 2, columnCount: 3
        )

        #expect(result.map { $0.compactMap { $0?.filename }.first } == [
            "B_1.png", "B_2.png", "B_3.png", "B_10.png", "A_2.png", "A_3.png", "A_10.png",
        ])
        #expect(result.allSatisfy { $0.count == 3 })
        #expect(result[1...5].allSatisfy { $0[0] == nil && $0[1] == nil && $0[2] != nil })
    }

    @Test
    func renamedContentMatchesKeepSerialInsertionOrderAndNumericSuffixes() {
        let rows: [[AssetRecord?]] = [[
            asset("A_1.png", folder: "reference"), asset("B_1.png", folder: "result"), nil,
        ]]
        let targets = ["A_10.png", "B_3.png", "A_2.png", "B_2.png"]
            .map { asset($0, folder: "third") }

        let result = CompareRowInsertionService.inserting(
            targets, into: rows, column: 2, columnCount: 3
        )

        #expect(result.map { $0.compactMap { $0?.filename }.first } == [
            "A_1.png", "B_2.png", "B_3.png", "A_2.png", "A_10.png",
        ])
        #expect(result.dropFirst().allSatisfy { $0[0] == nil && $0[1] == nil && $0[2] != nil })
    }

    private func asset(_ filename: String, folder: String) -> AssetRecord {
        AssetRecord(
            libraryID: UUID(), filename: filename, relativePath: "\(folder)/\(filename)",
            format: .png, fileSizeBytes: 100, width: 100, height: 100
        )
    }
}
