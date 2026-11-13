import Foundation
import PhotoTriageCore
import Testing

@MainActor
struct AppStateFolderFilteringTests {
    @Test
    func buildsFolderTreeFromLibraryAssets() async throws {
        let snapshot = makeSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        let tree = state.folderTree(for: library.id)

        #expect(tree.map(\.name) == ["exports", "set-a", "set-b"])
        #expect(tree.first(where: { $0.name == "set-a" })?.assetCount == 2)
        #expect(tree.first(where: { $0.name == "set-a" })?.children.map(\.name) == ["alts"])
        #expect(tree.first(where: { $0.name == "set-a" })?.children.first?.relativePath == "set-a/alts")
    }

    @Test
    func selectingFolderFiltersAssetsBySubtree() async throws {
        let snapshot = makeSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.selectFolder(in: library.id, relativePath: "set-a")

        #expect(state.selectedLibraryID == library.id)
        #expect(state.selectedFolderPath == "set-a")
        #expect(state.filteredAssets.map(\.relativePath) == [
            "set-a/cover.jpg",
            "set-a/alts/detail.heic",
        ])
    }

    @Test
    func selectingLibraryRootClearsFolderFilter() async throws {
        let snapshot = makeSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.selectFolder(in: library.id, relativePath: "set-a")
        state.selectLibrary(library.id)

        #expect(state.selectedFolderPath == nil)
        #expect(state.filteredAssets.count == 4)
    }

    @Test
    func togglingFolderSelectionFiltersMultipleSubtreesAndCanCancelOne() async throws {
        let snapshot = makeSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "set-a")
        state.toggleFolderSelection(in: library.id, relativePath: "set-b")

        #expect(state.selectedFolderPath == nil)
        #expect(state.selectedFolderPaths == ["set-a", "set-b"])
        #expect(state.filteredAssets.map(\.relativePath) == [
            "set-a/cover.jpg",
            "set-a/alts/detail.heic",
            "set-b/hero.jpg",
        ])

        state.toggleFolderSelection(in: library.id, relativePath: "set-a")

        #expect(state.selectedFolderPath == "set-b")
        #expect(state.filteredAssets.map(\.relativePath) == ["set-b/hero.jpg"])
    }

    @Test
    func compareGroupsFollowFolderClickOrderAndExcludeUnselectedFolders() async throws {
        let snapshot = makeFolderCompareSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "variant-c")

        #expect(state.selectedFolderOrder == ["result-b", "original-a", "variant-c"])
        #expect(state.filteredAssets.map(\.relativePath) == [
            "result-b/shared.jpg",
            "original-a/shared.jpg",
            "variant-c/shared.jpg",
        ])

        state.enterCompareMode()

        #expect(state.compareAssets.map(\.relativePath) == [
            "result-b/shared.jpg",
            "original-a/shared.jpg",
            "variant-c/shared.jpg",
        ])
        #expect(!state.compareAssets.map(\.relativePath).contains("unselected/shared.jpg"))
    }

    @Test
    func visibleCompareRowsAlignSelectedFoldersByBasename() async throws {
        let snapshot = makeMultiFolderCompareSnapshot(folderCount: 4)
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")
        state.toggleFolderSelection(in: library.id, relativePath: "variant-c")
        state.toggleFolderSelection(in: library.id, relativePath: "variant-d")

        #expect(state.visibleCompareRows.count == 2)
        #expect(state.visibleCompareRows.allSatisfy { $0.count == 4 })
        #expect(state.visibleCompareRows[0].compactMap { $0?.relativePath } == [
            "original-a/001.jpg",
            "result-b/001.jpg",
            "variant-c/001.jpg",
            "variant-d/001.jpg",
        ])
        #expect(state.visibleCompareRows[1].compactMap { $0?.relativePath } == [
            "original-a/002.jpg",
            "result-b/002.jpg",
            "variant-c/002.jpg",
            "variant-d/002.jpg",
        ])
    }

    @Test
    func visibleCompareRowsKeepTwoSelectedFoldersInOneRowPerPair() async throws {
        let snapshot = makeMultiFolderCompareSnapshot(folderCount: 2)
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")

        #expect(state.visibleCompareRows.map { $0.compactMap { $0?.relativePath } } == [
            ["original-a/001.jpg", "result-b/001.jpg"],
            ["original-a/002.jpg", "result-b/002.jpg"],
        ])
    }

    @Test
    func multiFolderSuffixVariantsStayAfterTheirBaseRow() async throws {
        let snapshot = makeMultiFolderSuffixVariantSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")

        #expect(state.visibleCompareRows.map { $0.map { $0?.filename } } == [
            ["001.jpg", "001.jpg"],
            [nil, "001_2.jpg"],
            [nil, "001_3.jpg"],
            ["003.jpg", "003.jpg"],
        ])
    }

    @Test
    func multiFolderNumberedBaseKeepsLaterVersionsAdjacentInGridAndViewer() async throws {
        let stem = "006YwXgQgy1hd56dw3bvnj33dc4hshdy"
        let snapshot = makeNumberedBaseSuffixSnapshot(folderNames: ["平胸", "小胸"], stem: stem)
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))
        await state.reloadWorkspace()
        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "平胸")
        state.toggleFolderSelection(in: library.id, relativePath: "小胸")

        let expected: [[String?]] = [
            ["\(stem)_1.png", "\(stem)_1.png"],
            [nil, "\(stem)_2.png"],
            [nil, "\(stem)_3.png"],
            [nil, "\(stem)_10.png"],
            ["00408(1)_1.png", "00408(1)_1.png"],
        ]
        #expect(state.visibleCompareRows.map { $0.map { $0?.filename } } == expected)
        state.jumpToBasenameCompareGroup(number: 1, enterCompare: true)
        #expect(state.stepBasenameCompareGroup(delta: 1))
        #expect(state.currentBasenameCompareGroupNumber == 2)
        #expect(state.comparePaneAssets.map { $0?.filename } == expected[1])
        #expect(state.stepBasenameCompareGroup(delta: 1))
        #expect(state.comparePaneAssets.map { $0?.filename } == expected[2])
    }

    @Test
    func multiFolderVariantsIntroducedInLaterColumnKeepNumericOrder() async throws {
        let library = LibraryFolder(displayName: "后缀插入顺序", path: "/tmp/suffix-late-column", columnIndex: 0)
        let stem = "006YwXgQgy1hd56dw3bvnj33dc4hshdy"
        let folders = ["original-a", "result-b", "variant-c"]
        let filenamesByFolder: [[String]] = [
            ["\(stem)_1.png", "next_1.png"],
            ["\(stem)_1.png", "\(stem)_3.png", "\(stem)_10.png", "next_1.png"],
            ["\(stem)_1.png", "\(stem)_2.png", "\(stem)_3.png", "\(stem)_10.png", "next_1.png"],
        ]
        let assets = folders.enumerated().flatMap { index, folder in
            filenamesByFolder[index].map { filename in
                AssetRecord(
                    libraryID: library.id,
                    filename: filename,
                    relativePath: "\(folder)/\(filename)",
                    format: .png,
                    fileSizeBytes: 100,
                    width: 1,
                    height: 1
                )
            }
        }
        let snapshot = WorkspaceSnapshot(
            libraries: [library],
            assets: assets,
            compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
            keepFolderPath: "/tmp/Keep",
            rejectFolderPath: "/tmp/Reject"
        )
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))
        await state.reloadWorkspace()

        for folder in folders {
            state.toggleFolderSelection(in: library.id, relativePath: folder)
        }

        #expect(state.visibleCompareRows.map { $0.map { $0?.filename } } == [
            ["\(stem)_1.png", "\(stem)_1.png", "\(stem)_1.png"],
            [nil, nil, "\(stem)_2.png"],
            [nil, "\(stem)_3.png", "\(stem)_3.png"],
            [nil, "\(stem)_10.png", "\(stem)_10.png"],
            ["next_1.png", "next_1.png", "next_1.png"],
        ])
    }

    @Test
    func sixFolderNumberedVariantsStayAdjacentWhenSelectionOrderChanges() async throws {
        let folders = ["原图", "首帧", "平胸", "大胸", "小胸", "中胸"]
        let stem = "006YwXgQgy1hd56dw3bvnj33dc4hshdy"
        let snapshot = makeNumberedBaseSuffixSnapshot(folderNames: folders, stem: stem)
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))
        await state.reloadWorkspace()
        let library = try #require(state.libraries.first)
        for folder in folders {
            state.toggleFolderSelection(in: library.id, relativePath: folder)
        }

        #expect(state.visibleCompareRows.map { $0.compactMap { $0?.filename }.first } == [
            "\(stem)_1.png", "\(stem)_2.png", "\(stem)_3.png", "\(stem)_10.png", "00408(1)_1.png",
        ])
        #expect(state.visibleCompareRows.allSatisfy { $0.count == folders.count })
        #expect(state.visibleCompareRows.flatMap { $0.compactMap { $0?.id } }.count == snapshot.assets.count)

        // Removing and re-adding a folder must invalidate the pairing cache,
        // without moving numbered variants to the end of the list.
        state.toggleFolderSelection(in: library.id, relativePath: folders[0])
        #expect(state.visibleCompareRows.isEmpty == false)
        state.toggleFolderSelection(in: library.id, relativePath: folders[0])
        #expect(state.visibleCompareRows.map { $0.compactMap { $0?.filename }.first } == [
            "\(stem)_1.png", "\(stem)_2.png", "\(stem)_3.png", "\(stem)_10.png", "00408(1)_1.png",
        ])
    }

    @Test
    func jumpToSelectedFolderCompareGroupExposesRowScrollTarget() async throws {
        let snapshot = makeMultiFolderCompareSnapshot(folderCount: 2)
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")

        state.jumpToBasenameCompareGroup(number: 2, enterCompare: false)

        let row = try #require(state.visibleCompareRows.dropFirst().first)
        let rowFirstAsset = try #require(row.compactMap(\.self).first)

        #expect(state.currentBasenameCompareGroupNumber == 2)
        #expect(state.selectedAssetIDs == Set(row.compactMap { $0?.id }))
        #expect(state.currentCompareGroupScrollTargetAssetID == rowFirstAsset.id)
    }

    @Test
    func compareModeFolderSteppingUpdatesRowScrollTarget() async throws {
        let snapshot = makeMultiFolderCompareSnapshot(folderCount: 2)
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")
        state.jumpToBasenameCompareGroup(number: 1, enterCompare: true)

        let moved = state.stepBasenameCompareGroup(delta: 1)
        let row = try #require(state.visibleCompareRows.dropFirst().first)
        let rowFirstAsset = try #require(row.compactMap(\.self).first)

        #expect(moved)
        #expect(state.currentBasenameCompareGroupNumber == 2)
        #expect(state.compareSelectionIDs == row.compactMap { $0?.id })
        #expect(state.currentCompareGroupScrollTargetAssetID == rowFirstAsset.id)
    }

    @Test
    func visibleCompareRowsAlignSelectedFoldersByStemIgnoringExtension() async throws {
        let snapshot = makeMixedExtensionFolderCompareSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")

        #expect(state.visibleCompareRows.map { $0.compactMap { $0?.relativePath } } == [
            ["original-a/001.jpg", "result-b/001.png"],
            ["original-a/002.heic", "result-b/002.jpg"],
        ])
    }

    @Test
    func visibleCompareRowsPreserveColumnSlotsWhenSelectedFolderIsMissingFromGroup() async throws {
        let snapshot = makeSparseFolderCompareSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")
        state.toggleFolderSelection(in: library.id, relativePath: "variant-c")
        state.toggleFolderSelection(in: library.id, relativePath: "variant-d")

        let sparseRow = try #require(state.visibleCompareRows.first)

        #expect(sparseRow.count == 4)
        #expect(sparseRow[0]?.relativePath == "original-a/001.jpg")
        #expect(sparseRow[1]?.relativePath == "result-b/001.jpg")
        #expect(sparseRow[2] == nil)
        #expect(sparseRow[3]?.relativePath == "variant-d/001.jpg")
    }

    @Test
    func groupedViewerKeepsEmptyMiddlePaneAndNumberedActionsDoNotShift() async throws {
        let snapshot = makePlaceholderCompareSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))
        await state.reloadWorkspace()
        state.jumpToBasenameCompareGroup(number: 2)

        #expect(state.comparePaneAssets.map { $0?.relativePath } == ["a/002.jpg", nil, "c/002.jpg"])
        #expect(state.isShowingCompareOverview)
        #expect(!state.isSingleImageCompareMode)
        #expect(state.compareAsset(atPane: 1) == nil)
        #expect(state.compareAsset(atPane: 2)?.relativePath == "c/002.jpg")
        #expect(state.cyclicOverlayAssetID(forAssetAt: 0) == nil)
        #expect(state.cyclicOverlayAssetID(forAssetAt: 1) == nil)
        #expect(state.cyclicOverlayAssetID(forAssetAt: 2) == state.compareAsset(atPane: 0)?.id)

        state.setBaseCompareOverlay(slot: 2)
        #expect(state.isShowingCompareOverview)
        #expect(state.compareOverlayAsset == nil)
        state.setBaseCompareOverlay(slot: 3)
        #expect(state.compareOverlayAsset?.relativePath == "c/002.jpg")
        state.toggleCompareOverlay(slot: 2)
        #expect(state.compareOverlayAsset?.relativePath == "c/002.jpg")
    }

    @Test
    func groupedViewerStepsThroughSparseRowsWithoutBecomingSingleImageViewer() async throws {
        let snapshot = makePlaceholderCompareSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))
        await state.reloadWorkspace()
        state.jumpToBasenameCompareGroup(number: 2)

        #expect(state.stepBasenameCompareGroup(delta: 1))
        #expect(state.comparePaneAssets.map { $0?.relativePath } == ["a/003.jpg", nil, nil])
        #expect(state.currentBasenameCompareGroupNumber == 3)
        #expect(!state.isSingleImageCompareMode)
        #expect(state.isShowingCompareOverview)

        state.applyRating(.keep, to: state.compareSelectionIDs)
        await state.reloadWorkspace(resetPresentation: false)
        #expect(state.comparePaneAssets.map { $0?.relativePath } == ["a/003.jpg", nil, nil])
        #expect(!state.isSingleImageCompareMode)

        #expect(state.stepBasenameCompareGroup(delta: 1))
        #expect(state.comparePaneAssets.map { $0?.relativePath } == ["a/004.jpg", "b/004.jpg", "c/004.jpg"])
        #expect(state.currentBasenameCompareGroupNumber == 4)
        #expect(state.stepBasenameCompareGroup(delta: -1))
        #expect(state.comparePaneAssets.map { $0?.relativePath } == ["a/003.jpg", nil, nil])
    }

    @Test
    func selectingAnAlignedThumbnailRowRetainsItsMissingPaneInCompare() async throws {
        let snapshot = makePlaceholderCompareSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))
        await state.reloadWorkspace()
        state.jumpToBasenameCompareGroup(number: 2, enterCompare: false)
        state.enterCompareMode()
        #expect(state.comparePaneAssets.map { $0?.relativePath } == ["a/002.jpg", nil, "c/002.jpg"])
    }

    @Test
    func explicitSingleImageViewerRemainsSingleEvenWhenOtherFoldersAreSelected() async throws {
        let snapshot = makePlaceholderCompareSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))
        await state.reloadWorkspace()
        let asset = try #require(state.assets.first { $0.relativePath == "a/002.jpg" })
        state.enterSingleImageViewer(assetID: asset.id)
        #expect(state.isSingleImageCompareMode)
        #expect(state.comparePaneAssets.map { $0?.id } == [asset.id])
    }

    @Test
    func groupedViewerKeepsLeadingPlaceholderWhenReferenceFileIsMissing() async throws {
        let snapshot = makePlaceholderCompareSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))
        await state.reloadWorkspace()
        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "b")
        state.toggleFolderSelection(in: library.id, relativePath: "a")
        let asset = try #require(state.assets.first { $0.relativePath == "a/003.jpg" })
        state.enterCompareModeForVisibleGroup(containing: asset.id)
        #expect(state.comparePaneAssets.map { $0?.relativePath } == [nil, "a/003.jpg"])
        #expect(state.isShowingCompareOverview)
        state.setBaseCompareOverlay(slot: 1)
        #expect(state.isShowingCompareOverview)
        state.setBaseCompareOverlay(slot: 2)
        #expect(state.compareFocusedAsset?.id == asset.id)
    }

    @Test
    func completeCompareRowsPairAssetsByFolderSortOrder() async throws {
        let snapshot = makeMixedCompletenessFolderCompareSnapshot()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: snapshot),
            imageContentFingerprintService: SemanticImageContentFingerprintService()
        )

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")
        await waitForImageContentMatching(state)

        #expect(state.visibleCompleteCompareRows.map { $0.compactMap { $0?.relativePath } } == [
            ["original-a/001.jpg", "result-b/001.jpg"],
            ["original-a/002.jpg", "result-b/003.jpg"],
        ])
        #expect(state.visibleThumbnailAssetCount == 4)
    }

    @Test
    func visibleAssetColumnsKeepOriginalFolderOrderWithoutBasenameMatching() async throws {
        let snapshot = makeMixedCompletenessFolderCompareSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")

        #expect(state.visibleAssetColumnsBySelectedFolder.map(\.folderPath) == ["original-a", "result-b"])
        #expect(state.visibleAssetColumnsBySelectedFolder[0].assets.map(\.relativePath) == [
            "original-a/001.jpg",
            "original-a/002.jpg",
        ])
        #expect(state.visibleAssetColumnsBySelectedFolder[1].assets.map(\.relativePath) == [
            "result-b/001.jpg",
            "result-b/003.jpg",
        ])
    }

    @Test
    func equalCountDifferentNamesAreNotMissingWhenPairingBySortOrder() async throws {
        let snapshot = makeMixedCompletenessFolderCompareSnapshot()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: snapshot),
            imageContentFingerprintService: SemanticImageContentFingerprintService()
        )

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")
        await waitForImageContentMatching(state)

        #expect(state.visibleCompareRows.map { $0.compactMap { $0?.relativePath } } == [
            ["original-a/001.jpg", "result-b/001.jpg"],
            ["original-a/002.jpg", "result-b/003.jpg"],
        ])
        #expect(state.missingCompareGroups.isEmpty)
    }

    @Test
    func multiFolderRowsUseFinderStyleNewestAddedDateFirst() async throws {
        let snapshot = makeAddedDatePairingSnapshot()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: snapshot),
            imageContentFingerprintService: SemanticImageContentFingerprintService()
        )

        await state.reloadWorkspace()
        state.selectAssetSortMode(.addedDate)

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")
        await waitForImageContentMatching(state)

        #expect(state.visibleCompareRows.map { $0.compactMap { $0?.relativePath } } == [
            ["original-a/source-newest.jpg", "result-b/output-newest.jpg"],
            ["original-a/source-middle.jpg", "result-b/output-middle.jpg"],
            ["original-a/source-oldest.jpg", "result-b/output-oldest.jpg"],
        ])
    }

    @Test
    func missingCompareGroupsOnlyListRowsWithEmptyFolderSlots() async throws {
        let snapshot = makeImbalancedFolderCompareSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")

        #expect(state.visibleCompareRows.count == 2)
        #expect(state.missingCompareGroups.map(\.displayName) == ["002.jpg"])
        #expect(state.missingCompareGroups[0].presentAssets.map(\.relativePath) == ["original-a/002.jpg"])
        #expect(state.missingCompareGroups[0].missingFolderPaths == ["result-b"])
    }

    @Test
    func missingCompareGroupsMatchByFilenameInsteadOfRowPosition() async throws {
        let snapshot = makeMissingMiddleFileCompareSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")

        #expect(state.missingCompareGroups.map(\.displayName) == ["002.jpg"])
        #expect(state.missingCompareGroups[0].presentAssets.map(\.relativePath) == ["original-a/002.jpg"])
        #expect(state.missingCompareGroups[0].missingFolderPaths == ["result-b"])
        #expect(state.missingCompareGroups[0].slots.map { $0?.filename } == ["002.jpg", nil])
        #expect(state.missingCompareAssetCount == 1)

        // Category filters must not hide scope-level missing-file diagnostics.
        state.selectCategoryFilter(.rating(.pending))
        #expect(state.missingCompareGroups.map(\.displayName) == ["002.jpg"])
        #expect(state.missingCompareAssetCount == 1)
    }

    @Test
    func twoStagePairingUsesFilenameThenThumbnailContentBeforeReportingMissing() async throws {
        let snapshot = makeTwoStageContentPairingSnapshot()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: snapshot),
            imageContentFingerprintService: SemanticImageContentFingerprintService()
        )

        await state.reloadWorkspace()
        let library = try #require(state.libraries.first)
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")

        #expect(state.isMatchingImageContent)
        #expect(state.missingCompareGroups.isEmpty)
        await waitForImageContentMatching(state)

        #expect(state.visibleCompareRows.prefix(3).map { $0.map { $0?.filename } } == [
            ["001.jpg", "001.png"],
            ["renamed-source.jpg", "different-output.png"],
            ["truly-missing.jpg", nil],
        ])
        #expect(state.missingCompareGroups.map(\.displayName) == ["truly-missing.jpg"])
        #expect(state.missingCompareAssetCount == 1)
    }

    @Test
    func suffixAliasesReserveTheSameRowsInFilenameAndContentMatching() async throws {
        let library = LibraryFolder(displayName: "后缀配对", path: "/tmp/suffix-alias-pairing", columnIndex: 0)
        let paths = [
            "original-a/photo_1.jpg", "original-a/photo_2.jpg",
            "result-b/photo_1.png", "result-b/photo_3.png",
            "variant-c/photo_3.png", "variant-c/output-photo_1.png",
        ]
        let assets = paths.map { path in
            AssetRecord(
                libraryID: library.id,
                filename: URL(fileURLWithPath: path).lastPathComponent,
                relativePath: path,
                format: path.hasSuffix(".jpg") ? .jpg : .png,
                fileSizeBytes: 100, width: 100, height: 100
            )
        }
        let snapshot = WorkspaceSnapshot(
            libraries: [library], assets: assets,
            compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
            keepFolderPath: "/tmp/Keep", rejectFolderPath: "/tmp/Reject"
        )
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: snapshot),
            imageContentFingerprintService: SemanticImageContentFingerprintService()
        )
        await state.reloadWorkspace()
        state.toggleFolderSelection(in: library.id, relativePath: "original-a")
        state.toggleFolderSelection(in: library.id, relativePath: "result-b")
        state.toggleFolderSelection(in: library.id, relativePath: "variant-c")
        await waitForImageContentMatching(state)

        #expect(state.visibleCompareRows.map { $0.map { $0?.filename } } == [
            ["photo_1.jpg", "photo_1.png", "output-photo_1.png"],
            ["photo_2.jpg", "photo_3.png", "photo_3.png"],
        ])
        #expect(state.missingCompareGroups.isEmpty)
    }

    @Test
    func libraryRootInfersTopLevelFoldersAsCompareColumns() async throws {
        let snapshot = makeMixedCompletenessFolderCompareSnapshot()
        let state = AppState(
            indexingService: StaticIndexingService(snapshot: snapshot),
            imageContentFingerprintService: SemanticImageContentFingerprintService()
        )

        await state.reloadWorkspace()
        await waitForImageContentMatching(state)

        #expect(state.compareFolderOrder == ["original-a", "result-b"])
        #expect(state.visibleCompleteCompareRows.map { $0.compactMap { $0?.relativePath } } == [
            ["original-a/001.jpg", "result-b/001.jpg"],
            ["original-a/002.jpg", "result-b/003.jpg"],
        ])
        #expect(state.visibleThumbnailAssetCount == 4)
        #expect(state.missingCompareGroups.isEmpty)
    }

    @Test
    func assetSortModeDefaultsToFilenameAndCanSwitchToAddedDate() async throws {
        let snapshot = makeSortModeSnapshot()
        let state = AppState(indexingService: StaticIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        #expect(state.assetSortMode == .filename)
        #expect(state.filteredAssets.map(\.filename) == ["a-earlier-name.jpg", "m-middle-name.jpg", "z-later-name.jpg"])

        state.selectAssetSortMode(.addedDate)

        #expect(state.assetSortMode == .addedDate)
        #expect(state.filteredAssets.map(\.filename) == ["m-middle-name.jpg", "a-earlier-name.jpg", "z-later-name.jpg"])
    }
}

private func makeSnapshot() -> WorkspaceSnapshot {
    let libraries = [
        LibraryFolder(displayName: "原图", path: "/tmp/originals", columnIndex: 0),
        LibraryFolder(displayName: "精修", path: "/tmp/retouched", columnIndex: 1),
    ]

    let assets = [
        AssetRecord(
            libraryID: libraries[0].id,
            filename: "cover.jpg",
            relativePath: "set-a/cover.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: libraries[0].id,
            filename: "detail.heic",
            relativePath: "set-a/alts/detail.heic",
            format: .heic,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: libraries[0].id,
            filename: "hero.jpg",
            relativePath: "set-b/hero.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: libraries[0].id,
            filename: "banner.webp",
            relativePath: "exports/banner.webp",
            format: .webp,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: libraries[1].id,
            filename: "cover.jpg",
            relativePath: "set-a/cover.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
    ]

    return WorkspaceSnapshot(
        libraries: libraries,
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: libraries, assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private func makeFolderCompareSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "工作区", path: "/tmp/workspace", columnIndex: 0)
    let assets = [
        AssetRecord(
            libraryID: library.id,
            filename: "shared.jpg",
            relativePath: "original-a/shared.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "shared.jpg",
            relativePath: "result-b/shared.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "shared.jpg",
            relativePath: "variant-c/shared.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "shared.jpg",
            relativePath: "unselected/shared.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private func makeSortModeSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "排序测试", path: "/tmp/sort", columnIndex: 0)
    let startDate = Date(timeIntervalSinceReferenceDate: 1_000)
    let assets = [
        AssetRecord(
            libraryID: library.id,
            filename: "m-middle-name.jpg",
            relativePath: "m-middle-name.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1,
            addedToDirectoryDate: startDate.addingTimeInterval(20)
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "z-later-name.jpg",
            relativePath: "z-later-name.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1,
            addedToDirectoryDate: startDate
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "a-earlier-name.jpg",
            relativePath: "a-earlier-name.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1,
            addedToDirectoryDate: startDate.addingTimeInterval(10)
        ),
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private func makeAddedDatePairingSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "排序配对", path: "/tmp/pairing", columnIndex: 0)
    let startDate = Date(timeIntervalSinceReferenceDate: 2_000)
    let assets = [
        AssetRecord(
            libraryID: library.id,
            filename: "source-oldest.jpg",
            relativePath: "original-a/source-oldest.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1,
            addedToDirectoryDate: startDate
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "output-oldest.jpg",
            relativePath: "result-b/output-oldest.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1,
            addedToDirectoryDate: startDate
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "source-newest.jpg",
            relativePath: "original-a/source-newest.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1,
            addedToDirectoryDate: startDate.addingTimeInterval(20)
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "output-newest.jpg",
            relativePath: "result-b/output-newest.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1,
            addedToDirectoryDate: startDate.addingTimeInterval(20)
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "source-middle.jpg",
            relativePath: "original-a/source-middle.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1,
            addedToDirectoryDate: startDate.addingTimeInterval(10)
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "output-middle.jpg",
            relativePath: "result-b/output-middle.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1,
            addedToDirectoryDate: startDate.addingTimeInterval(10)
        ),
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private func makeMultiFolderCompareSnapshot(folderCount: Int) -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "工作区", path: "/tmp/workspace", columnIndex: 0)
    let folders = Array(["original-a", "result-b", "variant-c", "variant-d"].prefix(folderCount))
    let assets = folders.flatMap { folder in
        [
            AssetRecord(
                libraryID: library.id,
                filename: "001.jpg",
                relativePath: "\(folder)/001.jpg",
                format: .jpg,
                fileSizeBytes: 100,
                width: 1,
                height: 1
            ),
            AssetRecord(
                libraryID: library.id,
                filename: "002.jpg",
                relativePath: "\(folder)/002.jpg",
                format: .jpg,
                fileSizeBytes: 100,
                width: 1,
                height: 1
            ),
        ]
    }

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private func makeMultiFolderSuffixVariantSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "后缀插入测试", path: "/tmp/suffix-insertion", columnIndex: 0)
    let assets = [
        ("original-a", "001.jpg", AssetFormat.jpg),
        ("original-a", "003.jpg", AssetFormat.jpg),
        ("result-b", "001.jpg", AssetFormat.jpg),
        ("result-b", "001_2.jpg", AssetFormat.jpg),
        ("result-b", "001_3.jpg", AssetFormat.jpg),
        ("result-b", "003.jpg", AssetFormat.jpg),
    ].map { folder, filename, format in
        AssetRecord(
            libraryID: library.id,
            filename: filename,
            relativePath: "\(folder)/\(filename)",
            format: format,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        )
    }

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private func makeNumberedBaseSuffixSnapshot(folderNames: [String], stem: String) -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "多文件夹后缀测试", path: "/tmp/numbered-base-suffix", columnIndex: 0)
    let assets = folderNames.enumerated().flatMap { index, folder in
        let filenames = ["\(stem)_1.png", "00408(1)_1.png"]
            + (index == folderNames.count - 1 ? ["\(stem)_10.png", "\(stem)_3.png", "\(stem)_2.png"] : [])
        return filenames.map { filename in
            AssetRecord(
                libraryID: library.id, filename: filename, relativePath: "\(folder)/\(filename)",
                format: .png, fileSizeBytes: 100, width: 1, height: 1
            )
        }
    }
    return WorkspaceSnapshot(
        libraries: [library], assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep", rejectFolderPath: "/tmp/Reject"
    )
}

private func makePlaceholderCompareSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "占位符测试", path: "/tmp/placeholder-compare", columnIndex: 0)
    let assets = ["a", "b", "c"].flatMap { folder in
        (1...4).compactMap { number -> AssetRecord? in
            if number == 2 && folder == "b" { return nil }
            if number == 3 && folder != "a" { return nil }
            let filename = String(format: "%03d.jpg", number)
            return AssetRecord(libraryID: library.id, filename: filename, relativePath: "\(folder)/\(filename)", format: .jpg, fileSizeBytes: 100, width: 100, height: 100)
        }
    }
    return WorkspaceSnapshot(
        libraries: [library], assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep", rejectFolderPath: "/tmp/Reject"
    )
}

private func makeSparseFolderCompareSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "工作区", path: "/tmp/workspace", columnIndex: 0)
    let assets = [
        AssetRecord(
            libraryID: library.id,
            filename: "001.jpg",
            relativePath: "original-a/001.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "001.jpg",
            relativePath: "result-b/001.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "001.jpg",
            relativePath: "variant-d/001.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private func makeMixedExtensionFolderCompareSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "工作区", path: "/tmp/workspace", columnIndex: 0)
    let assets = [
        AssetRecord(
            libraryID: library.id,
            filename: "001.jpg",
            relativePath: "original-a/001.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "001.png",
            relativePath: "result-b/001.png",
            format: .png,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "002.heic",
            relativePath: "original-a/002.heic",
            format: .heic,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "002.jpg",
            relativePath: "result-b/002.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private func makeMixedCompletenessFolderCompareSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "工作区", path: "/tmp/workspace", columnIndex: 0)
    let assets = [
        AssetRecord(
            libraryID: library.id,
            filename: "001.jpg",
            relativePath: "original-a/001.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "001.jpg",
            relativePath: "result-b/001.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "002.jpg",
            relativePath: "original-a/002.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "003.jpg",
            relativePath: "result-b/003.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private func makeImbalancedFolderCompareSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "工作区", path: "/tmp/workspace", columnIndex: 0)
    let assets = [
        AssetRecord(
            libraryID: library.id,
            filename: "001.jpg",
            relativePath: "original-a/001.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "001.jpg",
            relativePath: "result-b/001.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "002.jpg",
            relativePath: "original-a/002.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private func makeMissingMiddleFileCompareSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "工作区", path: "/tmp/workspace", columnIndex: 0)
    let assets = [
        AssetRecord(
            libraryID: library.id,
            filename: "001.jpg",
            relativePath: "original-a/001.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "002.jpg",
            relativePath: "original-a/002.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "003.jpg",
            relativePath: "original-a/003.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "001.jpg",
            relativePath: "result-b/001.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "003.jpg",
            relativePath: "result-b/003.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 1,
            height: 1
        ),
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

private func makeTwoStageContentPairingSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "两重配对", path: "/tmp/two-stage-pairing", columnIndex: 0)
    let assets = [
        AssetRecord(
            libraryID: library.id,
            filename: "001.jpg",
            relativePath: "original-a/001.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 100,
            height: 100
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "renamed-source.jpg",
            relativePath: "original-a/renamed-source.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 100,
            height: 100
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "truly-missing.jpg",
            relativePath: "original-a/truly-missing.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 100,
            height: 100
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "001.png",
            relativePath: "result-b/001.png",
            format: .png,
            fileSizeBytes: 90,
            width: 100,
            height: 100
        ),
        AssetRecord(
            libraryID: library.id,
            filename: "different-output.png",
            relativePath: "result-b/different-output.png",
            format: .png,
            fileSizeBytes: 90,
            width: 100,
            height: 100
        ),
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/tmp/Keep",
        rejectFolderPath: "/tmp/Reject"
    )
}

@MainActor
private func waitForImageContentMatching(_ state: AppState) async {
    for _ in 0..<1_000 {
        guard state.isMatchingImageContent else { return }
        await Task.yield()
    }
    #expect(!state.isMatchingImageContent)
}

private struct SemanticImageContentFingerprintService: ImageContentFingerprinting {
    func fingerprints(
        for requests: [ImageContentFingerprintRequest]
    ) async -> [UUID: ImageContentFingerprint] {
        requests.reduce(into: [UUID: ImageContentFingerprint]()) { result, request in
            result[request.assetID] = semanticFingerprint(for: request.fileURL)
        }
    }

    private func semanticFingerprint(for fileURL: URL) -> ImageContentFingerprint {
        let stem = fileURL.deletingPathExtension().lastPathComponent.lowercased()
        let semanticKey: String
        switch stem {
        case "002", "003":
            semanticKey = "second-row"
        case "renamed-source", "different-output":
            semanticKey = "renamed-content"
        default:
            semanticKey = stem
                .replacingOccurrences(of: "source-", with: "")
                .replacingOccurrences(of: "output-", with: "")
        }

        var seed = semanticKey.utf8.reduce(UInt64(0xcbf29ce484222325)) { value, byte in
            (value ^ UInt64(byte)) &* 0x100000001b3
        }
        func nextValue() -> UInt64 {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return seed
        }

        let edgeWords = (0..<8).map { _ in nextValue() }
        let normalizedLuminance = (0..<256).map { _ in UInt8(truncatingIfNeeded: nextValue()) }
        return ImageContentFingerprint(
            edgeWords: edgeWords,
            normalizedLuminance: normalizedLuminance,
            meanRed: UInt8(truncatingIfNeeded: nextValue()),
            meanGreen: UInt8(truncatingIfNeeded: nextValue()),
            meanBlue: UInt8(truncatingIfNeeded: nextValue()),
            luminanceDeviation: 40,
            aspectRatio: 1
        )
    }
}

private struct StaticIndexingService: IndexingService {
    let snapshot: WorkspaceSnapshot

    func loadWorkspace() async throws -> WorkspaceSnapshot {
        snapshot
    }
}
