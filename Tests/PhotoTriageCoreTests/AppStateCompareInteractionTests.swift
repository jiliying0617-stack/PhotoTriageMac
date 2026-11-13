import Foundation
import PhotoTriageCore
import Testing

@MainActor
struct AppStateCompareInteractionTests {
    @Test
    func enterCompareModeKeepsOrderedSelectionAndStartsInOverview() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[2].id, snapshot.assets[0].id, snapshot.assets[1].id])

        state.enterCompareMode()

        #expect(state.mode == .compare)
        #expect(state.compareSelectionIDs == [snapshot.assets[0].id, snapshot.assets[1].id, snapshot.assets[2].id])
        #expect(state.compareFocusedAsset == snapshot.assets[0])
        #expect(state.compareOverlayAsset == nil)
        #expect(state.isShowingCompareOverview)
    }

    @Test
    func enterCompareModeUsesThumbnailSelectionOrder() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.toggleSelection(assetID: snapshot.assets[2].id)
        state.toggleSelection(assetID: snapshot.assets[0].id)
        state.toggleSelection(assetID: snapshot.assets[1].id)

        state.enterCompareMode()

        #expect(state.compareSelectionIDs == [snapshot.assets[2].id, snapshot.assets[0].id, snapshot.assets[1].id])
    }


    @Test
    func focusCompareAssetEntersDetailAndClearsOverlay() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[0].id, snapshot.assets[1].id, snapshot.assets[2].id])
        state.enterCompareMode()
        state.toggleCompareOverlay(slot: 2)

        state.focusCompareAsset(snapshot.assets[2].id)

        #expect(!state.isShowingCompareOverview)
        #expect(state.compareFocusedAsset == snapshot.assets[2])
        #expect(state.compareOverlayAsset == nil)
        #expect(state.selectedAssetID == snapshot.assets[2].id)
    }

    @Test
    func enteringCompareModeMarksWholeGroupViewedBeforeAnyRating() async throws {
        let snapshot = makeBasenameCompareNavigationSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.select(assetID: snapshot.assets[0].id)

        state.enterCompareModeForCurrentBasenameGroup()

        #expect(state.isAssetInViewedCompareGroup(snapshot.assets[0].id))
        #expect(state.isAssetInViewedCompareGroup(snapshot.assets[1].id))

        state.showUnreviewedOnly = true

        #expect(state.filteredAssets.map(\.filename) == ["b.jpg", "b.png"])
        #expect(!state.filteredAssets.map(\.filename).contains("a.jpg"))
        #expect(!state.filteredAssets.map(\.filename).contains("a.png"))

        state.showUnreviewedOnly = false

        #expect(state.filteredAssets.map(\.filename) == ["a.jpg", "a.png", "b.jpg", "b.png"])
        #expect(state.isAssetInViewedCompareGroup(snapshot.assets[0].id))
    }

    @Test
    func unreviewedFilterHidesViewedCompareGroupAndRestoresWhenDisabled() async throws {
        let snapshot = makeBasenameCompareNavigationSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.applyRating(.keep, to: [snapshot.assets[0].id])
        state.select(assetID: snapshot.assets[0].id)
        state.enterCompareModeForCurrentBasenameGroup()
        state.focusCompareAsset(snapshot.assets[1].id)

        state.showUnreviewedOnly = true

        #expect(state.filteredAssets.map(\.filename) == ["b.jpg", "b.png"])
        #expect(state.compareAssets.map(\.filename) == ["b.jpg", "b.png"])
        #expect(state.isShowingCompareOverview)
        #expect(!state.filteredAssets.map(\.filename).contains("a.jpg"))
        #expect(!state.filteredAssets.map(\.filename).contains("a.png"))

        state.showUnreviewedOnly = false

        #expect(state.filteredAssets.map(\.filename) == ["a.jpg", "a.png", "b.jpg", "b.png"])
        #expect(state.filteredAssets.first { $0.filename == "a.jpg" }?.ratingState == .keep)
    }

    @Test
    func preservingReloadKeepsCurrentCompareGroupAndRefreshesAssetData() async throws {
        let snapshot = makeBasenameCompareNavigationSnapshot(fileSizeBytes: 100)
        let service = MutableCompareInteractionIndexingService(snapshot: snapshot)
        let state = AppState(indexingService: service)

        await state.reloadWorkspace()
        let originalAssetIDs = state.assets.map(\.id)
        let originalGlobalRefreshToken = state.imageRefreshToken
        let originalImageRefreshTokens = Dictionary(
            uniqueKeysWithValues: originalAssetIDs.map { ($0, state.imageRefreshToken(for: $0)) }
        )
        state.select(assetID: snapshot.assets[0].id)
        state.enterCompareModeForCurrentBasenameGroup()

        service.snapshot = makeBasenameCompareNavigationSnapshot(fileSizeBytes: 200)

        await state.requestPreservingWorkspaceReload()

        #expect(state.mode == .compare)
        #expect(state.compareAssets.map(\.filename) == ["a.jpg", "a.png"])
        #expect(state.compareAssets.map(\.fileSizeBytes) == [200, 200])
        #expect(state.isShowingCompareOverview)
        #expect(state.assets.map(\.id) == originalAssetIDs)
        #expect(state.imageRefreshToken == originalGlobalRefreshToken)
        #expect(originalAssetIDs.allSatisfy { id in
            state.imageRefreshToken(for: id) != originalImageRefreshTokens[id]
        })
    }

    @Test
    func preservingReloadKeepsStableImageIdentityAndCacheTokensWhenFilesAreUnchanged() async throws {
        let snapshot = makeBasenameCompareNavigationSnapshot(fileSizeBytes: 100)
        let service = MutableCompareInteractionIndexingService(snapshot: snapshot)
        let state = AppState(indexingService: service)

        await state.reloadWorkspace()
        let originalLibraryIDs = state.libraries.map(\.id)
        let originalAssetIDs = state.assets.map(\.id)
        let originalGlobalRefreshToken = state.imageRefreshToken
        let originalImageRefreshTokens = Dictionary(
            uniqueKeysWithValues: originalAssetIDs.map { ($0, state.imageRefreshToken(for: $0)) }
        )

        service.snapshot = makeBasenameCompareNavigationSnapshot(fileSizeBytes: 100)
        await state.requestPreservingWorkspaceReload()

        #expect(state.libraries.map(\.id) == originalLibraryIDs)
        #expect(state.assets.map(\.id) == originalAssetIDs)
        #expect(state.imageRefreshToken == originalGlobalRefreshToken)
        #expect(originalAssetIDs.allSatisfy { id in
            state.imageRefreshToken(for: id) == originalImageRefreshTokens[id]
        })
    }

    @Test
    func numberedOverlayDetailMarksWholeCompareGroupViewedForUnreviewedFilter() async throws {
        let snapshot = makeBasenameCompareNavigationSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.select(assetID: snapshot.assets[0].id)
        state.enterCompareModeForCurrentBasenameGroup()

        state.setBaseCompareOverlay(slot: 2)
        state.showUnreviewedOnly = true

        #expect(state.filteredAssets.map(\.filename) == ["b.jpg", "b.png"])
    }

    @Test
    func unreviewedFilterKeepsRequestedGroupVisibleWhenEnteringCompareMode() async throws {
        let snapshot = makeBasenameCompareNavigationSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.showUnreviewedOnly = true
        state.select(assetID: snapshot.assets[0].id)
        state.enterCompareModeForCurrentBasenameGroup()

        #expect(state.filteredAssets.map(\.filename) == ["a.jpg", "a.png", "b.jpg", "b.png"])
        #expect(state.compareAssets.map(\.filename) == ["a.jpg", "a.png"])
        #expect(state.isShowingCompareOverview)

        state.showUnreviewedOnly = false

        #expect(state.filteredAssets.map(\.filename) == ["a.jpg", "a.png", "b.jpg", "b.png"])
    }

    @Test
    func toggleCompareOverlayUsesNumberedSlotsAndSkipsFocusedAsset() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[0].id, snapshot.assets[1].id, snapshot.assets[2].id])
        state.enterCompareMode()
        state.focusCompareAsset(snapshot.assets[1].id)

        state.toggleCompareOverlay(slot: 2)
        #expect(state.compareOverlayAsset == nil)

        state.toggleCompareOverlay(slot: 1)
        #expect(state.compareOverlayAsset == snapshot.assets[0])

        state.toggleCompareOverlay(slot: 3)
        #expect(state.compareOverlayAsset == snapshot.assets[2])

        state.toggleCompareOverlay(slot: 3)
        #expect(state.compareOverlayAsset == nil)
    }

    @Test
    func baseCompareOverlayPinsFirstAssetAndSetsNumberedOverlay() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[0].id, snapshot.assets[1].id, snapshot.assets[2].id])
        state.enterCompareMode()
        state.focusCompareAsset(snapshot.assets[2].id)

        state.setBaseCompareOverlay(slot: 3)

        #expect(state.compareFocusedAsset == snapshot.assets[0])
        #expect(state.compareOverlayAsset == snapshot.assets[2])
        #expect(state.selectedAssetID == snapshot.assets[0].id)

        state.setBaseCompareOverlay(slot: 1)

        #expect(state.compareFocusedAsset == snapshot.assets[0])
        #expect(state.compareOverlayAsset == nil)
    }

    @Test
    func numberedOverlayFromOverviewUsesFirstAssetAsBaseAndSlotAsTarget() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[0].id, snapshot.assets[1].id, snapshot.assets[2].id])
        state.enterCompareMode()

        state.setBaseCompareOverlay(slot: 3)

        #expect(!state.isShowingCompareOverview)
        #expect(state.compareFocusedAsset == snapshot.assets[0])
        #expect(state.compareOverlayAsset == snapshot.assets[2])
        #expect(state.selectedAssetID == snapshot.assets[0].id)
    }

    @Test
    func showCompareOverviewReturnsFromNumberedOverlayDetail() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[0].id, snapshot.assets[1].id, snapshot.assets[2].id])
        state.enterCompareMode()
        state.setBaseCompareOverlay(slot: 2)

        state.showCompareOverview()

        #expect(state.mode == .compare)
        #expect(state.isShowingCompareOverview)
        #expect(state.compareFocusedAsset == snapshot.assets[0])
        #expect(state.compareOverlayAsset == nil)
    }

    @Test
    func cyclicOverlayMappingUsesNextPaneWithLastWrappingToFirst() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[0].id, snapshot.assets[1].id, snapshot.assets[2].id])
        state.enterCompareMode()

        #expect(state.cyclicOverlayAssetID(forAssetAt: 0) == snapshot.assets[1].id)
        #expect(state.cyclicOverlayAssetID(forAssetAt: 1) == snapshot.assets[2].id)
        #expect(state.cyclicOverlayAssetID(forAssetAt: 2) == snapshot.assets[0].id)
        #expect(state.cyclicOverlayAssetID(forAssetAt: 3) == nil)
    }

    @Test
    func showCompareOverviewStaysInCompareModeAndClearsDetailOverlay() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[0].id, snapshot.assets[1].id, snapshot.assets[2].id])
        state.enterCompareMode()
        state.focusCompareAsset(snapshot.assets[2].id)
        state.toggleCompareOverlay(slot: 1)

        state.showCompareOverview()

        #expect(state.mode == .compare)
        #expect(state.isShowingCompareOverview)
        #expect(state.compareFocusedAsset == snapshot.assets[0])
        #expect(state.compareOverlayAsset == nil)
        #expect(state.selectedAssetID == snapshot.assets[0].id)
    }

    @Test
    func temporaryOverlayUsesFirstNonFocusedAssetAndClearsOnEnd() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[0].id, snapshot.assets[1].id, snapshot.assets[2].id])
        state.enterCompareMode()
        state.focusCompareAsset(snapshot.assets[1].id)

        state.beginTemporaryOverlay(slot: 1)
        #expect(state.temporaryCompareOverlayAsset == snapshot.assets[0])
        #expect(state.effectiveCompareOverlayAsset == snapshot.assets[0])

        state.endTemporaryOverlay()
        #expect(state.temporaryCompareOverlayAsset == nil)
        #expect(state.effectiveCompareOverlayAsset == nil)
    }

    @Test
    func toggleOverlayABSkipsFocusedAssetWhenChoosingTemporaryOverlay() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[0].id, snapshot.assets[1].id, snapshot.assets[2].id])
        state.enterCompareMode()
        state.focusCompareAsset(snapshot.assets[1].id)

        state.toggleOverlayAB()
        #expect(state.temporaryCompareOverlayAsset == snapshot.assets[0])
        #expect(state.effectiveCompareOverlayAsset == snapshot.assets[0])
    }

    @Test
    func exitCompareModeReturnsToGridAndClearsComparePresentationState() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[0].id, snapshot.assets[1].id, snapshot.assets[2].id])
        state.enterCompareMode()
        state.focusCompareAsset(snapshot.assets[2].id)
        state.toggleCompareOverlay(slot: 1)

        state.exitCompareMode()

        #expect(state.mode == .grid)
        #expect(state.compareSelectionIDs.isEmpty)
        #expect(state.compareFocusedAsset == nil)
        #expect(state.compareOverlayAsset == nil)
        #expect(state.selectedAssetID == snapshot.assets[2].id)
    }

    @Test
    func enterCompareModeFallsBackToCurrentBasenameGroup() async throws {
        let library = LibraryFolder(displayName: "One Root", path: "/imports/one-root", columnIndex: 0)
        let assets = [
            AssetRecord(
                id: UUID(),
                libraryID: library.id,
                filename: "000021_input.jpg",
                relativePath: "第三波/原图/000021_input.jpg",
                format: .jpg,
                fileSizeBytes: 100,
                width: 1,
                height: 1
            ),
            AssetRecord(
                id: UUID(),
                libraryID: library.id,
                filename: "000021_input.png",
                relativePath: "第三波/结果图/000021_input.png",
                format: .png,
                fileSizeBytes: 100,
                width: 1,
                height: 1
            )
        ]
        let snapshot = WorkspaceSnapshot(
            libraries: [library],
            assets: assets,
            compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
            keepFolderPath: "/exports/Keep",
            rejectFolderPath: "/exports/Reject"
        )
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.select(assetID: assets[0].id)

        state.enterCompareModeForCurrentBasenameGroup()

        #expect(state.mode == .compare)
        #expect(Set(state.compareSelectionIDs) == Set(assets.map(\.id)))
        #expect(state.basenameCompareGroupCount == 1)
    }

    @Test
    func enterCompareModeUsesOnlyExplicitSelectionWhenMultipleAssetsAreSelected() async throws {
        let snapshot = makeFourAssetSingleBasenameSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[1].id, snapshot.assets[3].id])

        state.enterCompareMode()

        #expect(state.mode == .compare)
        #expect(state.isShowingCompareOverview)
        #expect(state.compareSelectionIDs == [snapshot.assets[1].id, snapshot.assets[3].id])
        #expect(state.compareAssets.map(\.filename) == ["same-b.jpg", "same-d.jpg"])
    }

    @Test
    func enterCompareModeSupportsSingleSelectedAssetAsViewer() async throws {
        let snapshot = makeSingleAssetSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.select(assetID: snapshot.assets[0].id)

        state.enterCompareMode()

        #expect(state.mode == .compare)
        #expect(state.compareSelectionIDs == [snapshot.assets[0].id])
        #expect(state.compareFocusedAsset == snapshot.assets[0])
        #expect(state.isSingleImageCompareMode)
        #expect(!state.isShowingCompareOverview)
    }

    @Test
    func enterCompareModeUsesSingleSelectedAssetWithoutPullingSequentialPair() async throws {
        let snapshot = makeSingleFolderNavigationSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.select(assetID: snapshot.assets[1].id)

        state.enterCompareMode()

        #expect(state.mode == .compare)
        #expect(state.compareAssets.map(\.filename) == ["002.jpg"])
        #expect(state.isSingleImageCompareMode)
        #expect(state.compareFocusedAsset?.filename == "002.jpg")
        #expect(!state.isShowingCompareOverview)
    }

    @Test
    func singleImageViewerStepsThroughVisibleAssetsOneByOne() async throws {
        let snapshot = makeSingleFolderNavigationSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.enterSingleImageViewer(assetID: snapshot.assets[1].id)

        let movedForward = state.stepBasenameCompareGroup(delta: 1)

        #expect(movedForward)
        #expect(state.compareAssets.map(\.filename) == ["003.jpg"])
        #expect(state.isSingleImageCompareMode)
        #expect(!state.isShowingCompareOverview)

        let movedBackward = state.stepBasenameCompareGroup(delta: -1)

        #expect(movedBackward)
        #expect(state.compareAssets.map(\.filename) == ["002.jpg"])
        #expect(state.isSingleImageCompareMode)
        #expect(!state.isShowingCompareOverview)
    }

    @Test
    func stepBasenameCompareGroupKeepsPlaceholderWhenOnlyOneFileIsPresent() async throws {
        let snapshot = makeMixedSingleAndPairedViewerSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.select(assetID: snapshot.assets[0].id)
        state.enterCompareModeForCurrentBasenameGroup()

        #expect(state.compareAssets.map(\.filename) == ["a.jpg", "a.png"])

        let movedForward = state.stepBasenameCompareGroup(delta: 1)

        #expect(movedForward)
        #expect(state.compareAssets.map(\.filename) == ["b.jpg"])
        #expect(state.compareFocusedAsset?.filename == "b.jpg")
        #expect(state.comparePaneAssets.map { $0?.filename } == ["b.jpg", nil])
        #expect(!state.isSingleImageCompareMode)
        #expect(state.isShowingCompareOverview)
        #expect(state.stepBasenameCompareGroup(delta: -1))
        #expect(state.comparePaneAssets.map { $0?.filename } == ["a.jpg", "a.png"])
    }

    @Test
    func stepBasenameCompareGroupMovesBetweenCompareSets() async throws {
        let snapshot = makeBasenameCompareNavigationSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.select(assetID: snapshot.assets[0].id)
        state.enterCompareModeForCurrentBasenameGroup()

        #expect(state.compareAssets.map(\.filename) == ["a.jpg", "a.png"])

        let movedForward = state.stepBasenameCompareGroup(delta: 1)
        #expect(movedForward)
        #expect(state.compareAssets.map(\.filename) == ["b.jpg", "b.png"])
        #expect(state.compareFocusedAsset?.filename == "b.jpg")
        #expect(state.isShowingCompareOverview)

        let movedBackward = state.stepBasenameCompareGroup(delta: -1)
        #expect(movedBackward)
        #expect(state.compareAssets.map(\.filename) == ["a.jpg", "a.png"])
        #expect(state.compareFocusedAsset?.filename == "a.jpg")
        #expect(state.isShowingCompareOverview)
    }

    @Test
    func jumpToBasenameCompareGroupSelectsWholeGroupInGridMode() async throws {
        let snapshot = makeBasenameCompareNavigationSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()

        state.jumpToBasenameCompareGroup(number: 2, enterCompare: false)

        let expectedIDs = Set(snapshot.assets[2...3].map(\.id))
        #expect(state.mode == .grid)
        #expect(state.selectedAssetIDs == expectedIDs)
        #expect(state.selectedAssetID == snapshot.assets[2].id)
        #expect(state.currentBasenameCompareGroupNumber == 2)
    }

    @Test
    func jumpToBasenameCompareGroupRefreshesOpenCompareSession() async throws {
        let snapshot = makeBasenameCompareNavigationSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.select(assetID: snapshot.assets[0].id)
        state.enterCompareModeForCurrentBasenameGroup()

        state.jumpToBasenameCompareGroup(number: 2, enterCompare: false)

        let expectedIDs = Set(snapshot.assets[2...3].map(\.id))
        #expect(state.mode == .compare)
        #expect(state.compareAssets.map(\.filename) == ["b.jpg", "b.png"])
        #expect(state.selectedAssetIDs == expectedIDs)
        #expect(state.selectedAssetID == snapshot.assets[2].id)
        #expect(state.currentBasenameCompareGroupNumber == 2)
        #expect(state.isShowingCompareOverview)
    }

    @Test
    func stepBasenameCompareGroupReturnsToOverviewWhenStartedFromDetail() async throws {
        let snapshot = makeBasenameCompareNavigationSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.select(assetID: snapshot.assets[0].id)
        state.enterCompareModeForCurrentBasenameGroup()
        state.focusCompareAsset(snapshot.assets[1].id)

        #expect(!state.isShowingCompareOverview)

        let movedForward = state.stepBasenameCompareGroup(delta: 1)

        #expect(movedForward)
        #expect(state.compareAssets.map(\.filename) == ["b.jpg", "b.png"])
        #expect(state.isShowingCompareOverview)
        #expect(state.compareOverlayAsset == nil)
    }

    @Test
    func stepBasenameCompareGroupCanMoveForwardWhenUnreviewedFilterHidesCurrentGroup() async throws {
        let snapshot = makeThreeBasenameCompareNavigationSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.select(assetID: snapshot.assets[0].id)
        state.enterCompareModeForCurrentBasenameGroup()
        state.showUnreviewedOnly = true

        #expect(state.compareAssets.map(\.filename) == ["b.jpg", "b.png"])

        let movedForward = state.stepBasenameCompareGroup(delta: 1)

        #expect(movedForward)
        #expect(state.mode == .compare)
        #expect(state.compareAssets.map(\.filename) == ["c.jpg", "c.png"])
        #expect(state.isShowingCompareOverview)
    }

    @Test
    func stepBasenameCompareGroupFallsBackToSequentialBatchesInSingleFolder() async throws {
        let snapshot = makeSingleFolderNavigationSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.select(assetID: snapshot.assets[0].id)
        state.enterCompareModeForCurrentBasenameGroup()

        #expect(state.compareAssets.map(\.filename) == ["001.jpg", "002.jpg"])
        #expect(state.basenameCompareGroupCount == 2)

        let movedForward = state.stepBasenameCompareGroup(delta: 1)

        #expect(movedForward)
        #expect(state.compareAssets.map(\.filename) == ["003.jpg", "004.jpg"])
        #expect(state.compareFocusedAsset?.filename == "003.jpg")
        #expect(state.isShowingCompareOverview)
    }

    @Test
    func sameFolderCompareGroupsKeepTheFirstExplicitSelectionSizeAndFilenameOrder() async throws {
        let snapshot = makeSingleFolderNavigationSnapshot(assetCount: 8, reverseStorageOrder: true)
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        let firstFourIDs = Set(
            snapshot.assets
                .sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
                .prefix(4)
                .map(\.id)
        )
        state.setSelection(assetIDs: firstFourIDs)
        state.enterCompareMode()

        #expect(state.singleFolderCompareGroupSize == 4)
        #expect(state.compareAssets.map(\.filename) == ["001.jpg", "002.jpg", "003.jpg", "004.jpg"])
        #expect(state.basenameCompareGroupCount == 2)

        let movedForward = state.stepBasenameCompareGroup(delta: 1)

        #expect(movedForward)
        #expect(state.singleFolderCompareGroupSize == 4)
        #expect(state.compareAssets.map(\.filename) == ["005.jpg", "006.jpg", "007.jpg", "008.jpg"])
    }

    @Test
    func compareRatingAppliesToFocusedAssetOnly() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[0].id, snapshot.assets[1].id, snapshot.assets[2].id])
        state.enterCompareMode()
        state.focusCompareAsset(snapshot.assets[1].id)

        state.applyRating(.keep, to: [state.compareFocusedAsset!.id])

        #expect(state.assets.first { $0.id == snapshot.assets[0].id }?.ratingState == .pending)
        #expect(state.assets.first { $0.id == snapshot.assets[1].id }?.ratingState == .keep)
        #expect(state.assets.first { $0.id == snapshot.assets[2].id }?.ratingState == .pending)
    }

    @Test
    func pendingCategoryKeepsActiveCompareOrderAndFocusWhileRatingChanges() async throws {
        let snapshot = makeSingleFolderNavigationSnapshot(assetCount: 8)
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.selectCategoryFilter(.rating(.pending))
        let orderedAssets = snapshot.assets.sorted {
            $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
        }
        let firstGroup = Array(orderedAssets.prefix(4))
        state.setSelection(assetIDs: Set(firstGroup.map(\.id)))
        state.enterCompareMode()
        state.focusCompareAsset(firstGroup[2].id)

        state.applyRating(.keep, to: [firstGroup[2].id])

        #expect(state.compareSelectionIDs == firstGroup.map(\.id))
        #expect(state.compareFocusedAsset?.id == firstGroup[2].id)
        #expect(state.filteredAssets.map(\.id) == orderedAssets.map(\.id))

        state.exitCompareMode()

        #expect(!state.filteredAssets.map(\.id).contains(firstGroup[2].id))
        #expect(state.filteredAssets.map(\.id) == orderedAssets.filter { $0.id != firstGroup[2].id }.map(\.id))
    }

    @Test
    func rotatingFocusedAssetUpdatesOnlyFocusedCompareImage() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[0].id, snapshot.assets[1].id])
        state.enterCompareMode()
        state.focusCompareAsset(snapshot.assets[1].id)

        state.rotateFocusedAsset(quarterTurns: 1)

        #expect(state.assets.first { $0.id == snapshot.assets[0].id }?.rotationDegrees == 0)
        #expect(state.assets.first { $0.id == snapshot.assets[1].id }?.rotationDegrees == 90)
    }

    @Test
    func rotatingCompareSelectionUpdatesEveryComparedImage() async throws {
        let snapshot = makeCompareInteractionSnapshot()
        let state = AppState(indexingService: StaticCompareInteractionIndexingService(snapshot: snapshot))

        await state.reloadWorkspace()
        state.setSelection(assetIDs: [snapshot.assets[0].id, snapshot.assets[1].id])
        state.enterCompareMode()

        state.rotateCompareSelection(quarterTurns: -1)

        #expect(state.assets.first { $0.id == snapshot.assets[0].id }?.rotationDegrees == 270)
        #expect(state.assets.first { $0.id == snapshot.assets[1].id }?.rotationDegrees == 270)
        #expect(state.assets.first { $0.id == snapshot.assets[2].id }?.rotationDegrees == 0)
    }
}

private func makeFourAssetSingleBasenameSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "Compare", path: "/imports/compare", columnIndex: 0)
    let assets = [
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "same-a.jpg",
            relativePath: "0-original/same.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "same-b.jpg",
            relativePath: "1-edit/same.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "same-c.jpg",
            relativePath: "2-edit/same.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "same-d.jpg",
            relativePath: "3-edit/same.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        )
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/exports/Keep",
        rejectFolderPath: "/exports/Reject"
    )
}

private func makeSingleAssetSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "Compare", path: "/imports/compare", columnIndex: 0)
    let assets = [
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "single.jpg",
            relativePath: "single.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        )
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/exports/Keep",
        rejectFolderPath: "/exports/Reject"
    )
}

private func makeMixedSingleAndPairedViewerSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "Compare", path: "/imports/compare", columnIndex: 0)
    let assets = [
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "a.jpg",
            relativePath: "0-original/a.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "a.png",
            relativePath: "1-result/a.png",
            format: .png,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "b.jpg",
            relativePath: "0-original/b.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        )
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/exports/Keep",
        rejectFolderPath: "/exports/Reject"
    )
}

private func makeThreeBasenameCompareNavigationSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "Compare", path: "/imports/compare", columnIndex: 0)
    let assets = [
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "a.jpg",
            relativePath: "0-original/a.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "a.png",
            relativePath: "1-result/a.png",
            format: .png,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "b.jpg",
            relativePath: "0-original/b.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "b.png",
            relativePath: "1-result/b.png",
            format: .png,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "c.jpg",
            relativePath: "0-original/c.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "c.png",
            relativePath: "1-result/c.png",
            format: .png,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        )
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/exports/Keep",
        rejectFolderPath: "/exports/Reject"
    )
}

private func makeCompareInteractionSnapshot() -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "Compare", path: "/imports/compare", columnIndex: 0)
    let assets = [
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "001.jpg",
            relativePath: "set/001.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "002.jpg",
            relativePath: "set/002.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "003.jpg",
            relativePath: "set/003.jpg",
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        )
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/exports/Keep",
        rejectFolderPath: "/exports/Reject"
    )
}

private func makeSingleFolderNavigationSnapshot(
    assetCount: Int = 4,
    reverseStorageOrder: Bool = false
) -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "Compare", path: "/imports/compare", columnIndex: 0)
    let indices = reverseStorageOrder
        ? Array((1...assetCount).reversed())
        : Array(1...assetCount)
    let assets = indices.map { index in
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: String(format: "%03d.jpg", index),
            relativePath: String(format: "%03d.jpg", index),
            format: .jpg,
            fileSizeBytes: 100,
            width: 4000,
            height: 3000
        )
    }

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/exports/Keep",
        rejectFolderPath: "/exports/Reject"
    )
}

private func makeBasenameCompareNavigationSnapshot(fileSizeBytes: Int64 = 100) -> WorkspaceSnapshot {
    let library = LibraryFolder(displayName: "Compare", path: "/imports/compare", columnIndex: 0)
    let assets = [
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "a.jpg",
            relativePath: "0-original/a.jpg",
            format: .jpg,
            fileSizeBytes: fileSizeBytes,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "a.png",
            relativePath: "1-result/a.png",
            format: .png,
            fileSizeBytes: fileSizeBytes,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "b.jpg",
            relativePath: "0-original/b.jpg",
            format: .jpg,
            fileSizeBytes: fileSizeBytes,
            width: 4000,
            height: 3000
        ),
        AssetRecord(
            id: UUID(),
            libraryID: library.id,
            filename: "b.png",
            relativePath: "1-result/b.png",
            format: .png,
            fileSizeBytes: fileSizeBytes,
            width: 4000,
            height: 3000
        )
    ]

    return WorkspaceSnapshot(
        libraries: [library],
        assets: assets,
        compareGroups: CompareGroupingService.buildGroups(libraries: [library], assets: assets),
        keepFolderPath: "/exports/Keep",
        rejectFolderPath: "/exports/Reject"
    )
}

private struct StaticCompareInteractionIndexingService: IndexingService {
    let snapshot: WorkspaceSnapshot

    func loadWorkspace() async throws -> WorkspaceSnapshot {
        snapshot
    }
}

private final class MutableCompareInteractionIndexingService: IndexingService, @unchecked Sendable {
    var snapshot: WorkspaceSnapshot

    init(snapshot: WorkspaceSnapshot) {
        self.snapshot = snapshot
    }

    func loadWorkspace() async throws -> WorkspaceSnapshot {
        snapshot
    }
}
