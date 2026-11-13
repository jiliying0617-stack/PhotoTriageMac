import PhotoTriageCore
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

public struct CompareCanvasView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var shortcuts: KeyboardShortcutStore
    @EnvironmentObject private var interactions: InteractionSettingsStore

    @State private var compareZoom: CGFloat = 1
    @State private var comparePan: CGSize = .zero
    @State private var toleranceThreshold = 0
    @State private var toleranceSliderValue: Double = 0
    @State private var showsSubToleranceDifferences = true
    @State private var isCyclicOverlayActive = false
    @State private var isToleranceViewVisible = false
    @State private var tolerancePanelHeight: CGFloat?
    @State private var toleranceResizeStartHeight: CGFloat?
    @State private var overviewScrollTargetID: UUID?
    @State private var overviewScrollPositionID: UUID?
    @State private var focusThumbnailScrollPositionID: UUID?
    @State private var hoveredCompareAssetID: UUID?
#if canImport(AppKit)
    @StateObject private var toleranceStore = CompareToleranceStore()
#endif

    private let minimumZoom: CGFloat = 1
    private let maximumZoom: CGFloat = 6

    public init() {}

    public var body: some View {
        ZStack {
            ComparePalette.canvas

            if !state.compareAssets.isEmpty {
                VStack(spacing: 0) {
                    compareShell
                }
            } else {
                ContentUnavailableView(
                    "先选一张图",
                    systemImage: "photo",
                    description: Text("回到网格选择素材后再进入大图查看")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            KeyEventMonitor(
                onKeyDown: handleKeyDown,
                onKeyUp: handleKeyUp
            )
            .frame(width: 0, height: 0)
        )
        .onAppear {
            resetActiveTransform()
            DispatchQueue.main.async {
                loadTolerancePairsIfVisible()
            }
        }
        .onChange(of: state.compareSelectionIDs) { previous, current in
            hoveredCompareAssetID = nil
            let filledMissingSlots = !state.compareSession.folderPaths.isEmpty && !previous.isEmpty
                && Set(previous).isSubset(of: Set(current)) && current.count > previous.count
            if !filledMissingSlots { resetActiveTransform() }
            if state.compareSelectionIDs.count < 2 {
                isToleranceViewVisible = false
            }
            if state.isShowingCompareOverview {
                requestOverviewScroll(to: state.compareSelectionIDs.first)
            }
            loadTolerancePairsIfVisible()
        }
        .onChange(of: state.isShowingCompareOverview) { _, _ in
            hoveredCompareAssetID = nil
        }
        .onChange(of: state.isSingleImageCompareMode) { _, _ in
            hoveredCompareAssetID = nil
        }
        .onChange(of: state.imageRefreshToken) { _, _ in
            loadTolerancePairsIfVisible()
        }
        .onChange(of: isToleranceViewVisible) { _, isVisible in
            if isVisible {
                loadTolerancePairsIfVisible()
            } else {
                toleranceStore.cancelPendingLoads()
            }
        }
        .onChange(of: toleranceStore.usesOriginalResolution) { _, _ in
            toleranceStore.cancelPendingLoads()
            loadTolerancePairsIfVisible()
        }
        .onDisappear { toleranceStore.cancelPendingLoads() }
        .alert(
            "图片旋转失败",
            isPresented: Binding(
                get: { state.rotationErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { state.dismissRotationError() }
                }
            )
        ) {
            Button("好") { state.dismissRotationError() }
        } message: {
            Text(state.rotationErrorMessage ?? "无法旋转本地图片。")
        }
    }

    private var compareShell: some View {
        Group {
            if state.isSingleImageCompareMode {
                compareDetail
            } else if state.isShowingCompareOverview {
                compareOverview
            } else {
                compareDetail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var compareOverview: some View {
        GeometryReader { proxy in
            let paneAssets = state.comparePaneAssets
            let paneCount = max(paneAssets.count, 1)
            let paneWidth = max(180, CompareLayoutMetrics.overviewPaneWidth(containerWidth: proxy.size.width, paneCount: paneCount))
            let contentWidth = max(
                proxy.size.width,
                (paneWidth * CGFloat(paneCount)) + CGFloat(max(paneCount - 1, 0))
            )
            let defaultToleranceHeight = CompareLayoutMetrics.toleranceOverviewHeight(containerHeight: proxy.size.height)
            let toleranceHeight = isToleranceViewVisible
                ? CompareLayoutMetrics.clampedToleranceHeight(
                    proposedHeight: tolerancePanelHeight ?? defaultToleranceHeight,
                    containerHeight: proxy.size.height,
                    reservedUpperHeight: 280
                )
                : 0
            let resizeHandleHeight = isToleranceViewVisible
                ? CompareLayoutMetrics.toleranceResizeHandleHeight
                : 0
            let comparisonHeight = max(proxy.size.height - toleranceHeight - resizeHandleHeight, 1)

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        HStack(spacing: 1) {
                            ForEach(Array(paneAssets.enumerated()), id: \.offset) { index, optionalAsset in
                                if let asset = optionalAsset {
                                    let cyclicOverlay = cyclicOverlayAsset(for: index)
                                    let layerVisibility = CompareCyclicOverlayBehavior.layerVisibility(
                                        isActive: isCyclicOverlayActive
                                    )

                                    CompareOverviewPane(
                                        asset: asset,
                                        fileURL: state.fileURL(for: asset),
                                        overlayAsset: cyclicOverlay,
                                        overlayFileURL: cyclicOverlay.flatMap { state.fileURL(for: $0) },
                                        overlayIsVisible: layerVisibility.cyclicOverlayIsVisible,
                                        refreshToken: state.imageRefreshToken(for: asset.id),
                                        overlayRefreshToken: cyclicOverlay.map { state.imageRefreshToken(for: $0.id) },
                                        index: index + 1,
                                        total: paneCount,
                                        floatingBadge: isCyclicOverlayActive ? cyclicOverlayPairLabel(forBaseIndex: index) : nil,
                                        zoomScale: compareZoom,
                                        pan: $comparePan,
                                        showsOverlayMarks: false,
                                        onActivate: {
                                            state.focusCompareAsset(asset.id)
                                            resetActiveTransform()
                                            loadTolerancePairsIfVisible()
                                        },
                                        onZoom: handleCompareWheelZoom,
                                        onRevealInFinder: {
                                            state.revealAssetInFinder(asset)
                                        },
                                        onApplyRating: { rating in
                                            state.applyRating(rating, to: [asset.id])
                                        },
                                        onApplyPriorityTag: { priorityTag in
                                            state.applyPriorityTag(priorityTag, to: [asset.id])
                                        },
                                        onClearPriorityTag: {
                                            state.clearPriorityTags(from: [asset.id])
                                        },
                                        onClearAllTags: {
                                            state.clearAllTriageTags(from: [asset.id])
                                        },
                                        onSaveGIF: { request in
                                            saveCompareGIF(request)
                                        },
                                        onHoverAsset: { assetID in
                                            hoveredCompareAssetID = assetID
                                        }
                                    )
                                    .frame(width: paneWidth, height: comparisonHeight)
                                    .id(asset.id)
                                } else {
                                    CompareMissingPane(
                                        subtitle: "(\(index + 1)/\(paneCount))  \(state.compareSession.folderPaths[index])"
                                    )
                                    .frame(width: paneWidth, height: comparisonHeight)
                                }
                            }
                        }
                        .scrollTargetLayout()
                        .frame(width: contentWidth, height: comparisonHeight, alignment: .leading)

                        if isToleranceViewVisible {
                            toleranceResizeHandle(
                                currentHeight: toleranceHeight,
                                containerHeight: proxy.size.height,
                                reservedUpperHeight: 280
                            )
                            .frame(width: contentWidth)

                            toleranceOverviewRow(
                                contentWidth: contentWidth,
                                height: toleranceHeight
                            )
                        }
                    }
                    .frame(width: contentWidth, height: proxy.size.height, alignment: .topLeading)
                    .background(ComparePalette.canvas)
                }
                .scrollPosition(id: $overviewScrollPositionID, anchor: .center)
                .scrollDisabled(paneCount <= 7)
                .onAppear {
                    scrollOverviewIfNeeded(scrollProxy)
                }
                .onChange(of: overviewScrollTargetID) { _, _ in
                    scrollOverviewIfNeeded(scrollProxy)
                }
            }
        }
    }

    @ViewBuilder
    private func toleranceOverviewRow(contentWidth: CGFloat, height: CGFloat) -> some View {
        let pairs = overviewTolerancePairs
        let pairPositions = CompareTolerancePairing.overviewPairs(assetCount: state.comparePaneAssets.count)
        let controlWidth = CompareLayoutMetrics.toleranceControlWidth(containerWidth: contentWidth)
        let resultsWidth = max(contentWidth - controlWidth, 1)
        let resultPaneWidth = max(
            (resultsWidth - CGFloat(max(pairPositions.count - 1, 0))) / CGFloat(max(pairPositions.count, 1)),
            1
        )

        HStack(spacing: 0) {
            HStack(spacing: 1) {
                ForEach(Array(pairPositions.enumerated()), id: \.offset) { _, position in
                    if let pair = makeTolerancePair(position) {
                        CompareTolerancePanel(
                            pair: pair,
                            zoomScale: compareZoom,
                            pan: $comparePan,
                            tolerance: toleranceThreshold,
                            showsSubToleranceDifferences: showsSubToleranceDifferences,
                            onZoom: handleCompareWheelZoom,
                            store: toleranceStore
                        )
                        .frame(width: resultPaneWidth, height: height)
                    } else {
                        CompareMissingPane(message: "缺少对比图片")
                            .frame(width: resultPaneWidth, height: height)
                    }
                }
            }
            .frame(width: resultsWidth, height: height, alignment: .leading)

            CompareToleranceControlPanel(
                pairs: pairs,
                tolerance: toleranceThreshold,
                toleranceSliderValue: $toleranceSliderValue,
                showsSubToleranceDifferences: $showsSubToleranceDifferences,
                onToleranceChange: setToleranceThreshold,
                onSubToleranceVisibilityChange: { isVisible in
                    loadTolerancePairsIfVisible(blueDifferencesVisible: isVisible)
                },
                store: toleranceStore
            )
            .frame(width: controlWidth, height: height)
        }
        .frame(width: contentWidth, height: height, alignment: .leading)
    }

    private func cyclicOverlayAsset(for index: Int) -> AssetRecord? {
        guard let overlayID = state.cyclicOverlayAssetID(forAssetAt: index) else { return nil }
        return state.compareAssets.first { $0.id == overlayID }
    }

    private func cyclicOverlayForFocusedAsset() -> AssetRecord? {
        guard let focusedAsset = state.compareFocusedAsset,
              let index = state.comparePaneAssets.firstIndex(where: { $0?.id == focusedAsset.id }) else {
            return nil
        }
        return cyclicOverlayAsset(for: index)
    }

    private func cyclicOverlayPairLabel(forBaseIndex baseIndex: Int) -> String? {
        guard let overlayAsset = cyclicOverlayAsset(for: baseIndex),
              let overlayIndex = state.comparePaneAssets.firstIndex(where: { $0?.id == overlayAsset.id }) else {
            return nil
        }

        return "叠图：#\(overlayIndex + 1) 叠到 #\(baseIndex + 1)"
    }

    private var focusedCyclicOverlayPairLabel: String? {
        guard let focusedAsset = state.compareFocusedAsset,
              let focusedIndex = state.comparePaneAssets.firstIndex(where: { $0?.id == focusedAsset.id }) else {
            return nil
        }

        return cyclicOverlayPairLabel(forBaseIndex: focusedIndex)
    }

    private var compareDetail: some View {
        GeometryReader { containerProxy in
            let defaultToleranceHeight = CompareLayoutMetrics.toleranceDetailHeight()
            let toleranceHeight = CompareLayoutMetrics.clampedToleranceHeight(
                proposedHeight: tolerancePanelHeight ?? defaultToleranceHeight,
                containerHeight: containerProxy.size.height,
                reservedUpperHeight: 360
            )

            VStack(spacing: 0) {
            if let focusedAsset = state.compareFocusedAsset {
                    let persistentOverlay = state.effectiveCompareOverlayAsset
                    let cyclicOverlay = cyclicOverlayForFocusedAsset()
                    let layerVisibility = CompareCyclicOverlayBehavior.layerVisibility(
                        isActive: isCyclicOverlayActive
                    )

                    CompareDetailStage(
                        focusedAsset: focusedAsset,
                        focusedFileURL: state.fileURL(for: focusedAsset),
                        overlayAsset: persistentOverlay,
                        overlayFileURL: persistentOverlay.flatMap { state.fileURL(for: $0) },
                        overlayIsVisible: layerVisibility.persistentOverlayIsVisible,
                        instantOverlayAsset: cyclicOverlay,
                        instantOverlayFileURL: cyclicOverlay.flatMap { state.fileURL(for: $0) },
                        instantOverlayIsVisible: layerVisibility.cyclicOverlayIsVisible,
                        refreshToken: state.imageRefreshToken(for: focusedAsset.id),
                        overlayRefreshToken: persistentOverlay.map { state.imageRefreshToken(for: $0.id) },
                        instantOverlayRefreshToken: cyclicOverlay.map { state.imageRefreshToken(for: $0.id) },
                        zoomScale: compareZoom,
                        pan: $comparePan,
                        locksOverlayToBaseGeometry: true,
                        showsOverlayMarks: !isCyclicOverlayActive,
                        floatingBadge: isCyclicOverlayActive ? focusedCyclicOverlayPairLabel : nil,
                        onZoom: handleCompareWheelZoom,
                        onRevealInFinder: {
                            state.revealAssetInFinder(focusedAsset)
                        },
                        onApplyRating: { rating in
                            state.applyRating(rating, to: [focusedAsset.id])
                        },
                        onApplyPriorityTag: { priorityTag in
                            state.applyPriorityTag(priorityTag, to: [focusedAsset.id])
                        },
                        onClearPriorityTag: {
                            state.clearPriorityTags(from: [focusedAsset.id])
                        },
                        onClearAllTags: {
                            state.clearAllTriageTags(from: [focusedAsset.id])
                        },
                        onSaveGIF: { request in
                            saveCompareGIF(request)
                        },
                        onHoverAsset: { assetID in
                            hoveredCompareAssetID = assetID
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isToleranceViewVisible, let pair = detailTolerancePair {
                        toleranceResizeHandle(
                            currentHeight: toleranceHeight,
                            containerHeight: containerProxy.size.height,
                            reservedUpperHeight: 360
                        )

                        GeometryReader { proxy in
                            let controlWidth = CompareLayoutMetrics.toleranceControlWidth(containerWidth: proxy.size.width)

                            HStack(spacing: 0) {
                                CompareTolerancePanel(
                                    pair: pair,
                                    zoomScale: compareZoom,
                                    pan: $comparePan,
                                    tolerance: toleranceThreshold,
                                    showsSubToleranceDifferences: showsSubToleranceDifferences,
                                    onZoom: handleCompareWheelZoom,
                                    store: toleranceStore
                                )

                                CompareToleranceControlPanel(
                                    pairs: [pair],
                                    tolerance: toleranceThreshold,
                                    toleranceSliderValue: $toleranceSliderValue,
                                    showsSubToleranceDifferences: $showsSubToleranceDifferences,
                                    onToleranceChange: setToleranceThreshold,
                                    onSubToleranceVisibilityChange: { isVisible in
                                        loadTolerancePairsIfVisible(blueDifferencesVisible: isVisible)
                                    },
                                    store: toleranceStore
                                )
                                .frame(width: controlWidth)
                            }
                        }
                        .frame(height: toleranceHeight)
                    }

                    VStack(spacing: 10) {
                        if !state.isSingleImageCompareMode {
                            overlayShortcutStrip
                        }
                        focusThumbnailStrip
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(ComparePalette.panel)
                }
            }
            .frame(width: containerProxy.size.width, height: containerProxy.size.height)
        }
        .background(ComparePalette.canvas)
    }

    private var overlayShortcutStrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(state.comparePaneAssets.prefix(9).enumerated()), id: \.offset) { index, asset in
                let slot = index + 1
                let isFocused = asset != nil && asset?.id == state.compareFocusedAsset?.id
                let isOverlaying = asset != nil && asset?.id == state.effectiveCompareOverlayAsset?.id

                Button {
                    state.setBaseCompareOverlay(slot: slot)
                    loadTolerancePairsIfVisible()
                } label: {
                    HStack(spacing: 8) {
                        Text("\(slot)")
                            .font(.caption.weight(.bold))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.12), in: Circle())
                        Text(asset?.filename ?? "缺少同名文件")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .disabled(isFocused || asset == nil)
                .help("按 \(shortcuts.map.displayKey(for: overlayAction(for: slot))) 设置叠图")
                .buttonStyle(CompareOverlayShortcutButtonStyle(isSelected: isOverlaying))
            }

            Spacer(minLength: 0)
        }
    }

    private var detailOverlayAsset: AssetRecord? {
        isCyclicOverlayActive ? cyclicOverlayForFocusedAsset() : state.effectiveCompareOverlayAsset
    }

    private var overviewTolerancePairs: [CompareTolerancePair] {
        CompareTolerancePairing.overviewPairs(assetCount: state.comparePaneAssets.count).compactMap(makeTolerancePair)
    }

    private var detailTolerancePair: CompareTolerancePair? {
        guard let focusedAsset = state.compareFocusedAsset,
              let focusedIndex = state.comparePaneAssets.firstIndex(where: { $0?.id == focusedAsset.id }) else {
            return nil
        }

        let selectedOverlayIndex = detailOverlayAsset.flatMap { overlayAsset in
            state.comparePaneAssets.firstIndex(where: { $0?.id == overlayAsset.id })
        }
        guard let pairIndices = CompareTolerancePairing.detailPair(
            assetCount: state.comparePaneAssets.count,
            focusedIndex: focusedIndex,
            selectedOverlayIndex: selectedOverlayIndex
        ) else {
            return nil
        }
        return makeTolerancePair(pairIndices)
    }

    private func makeTolerancePair(_ pair: CompareTolerancePairIndices) -> CompareTolerancePair? {
        guard let baseAsset = state.compareAsset(atPane: pair.baseIndex),
              let overlayAsset = state.compareAsset(atPane: pair.overlayIndex) else {
            return nil
        }
        return CompareTolerancePair(
            baseAsset: baseAsset,
            baseFileURL: state.fileURL(for: baseAsset),
            overlayAsset: overlayAsset,
            overlayFileURL: state.fileURL(for: overlayAsset),
            baseIndex: pair.baseIndex,
            overlayIndex: pair.overlayIndex,
            refreshSignature: [
                state.imageRefreshToken(for: baseAsset.id).uuidString,
                state.imageRefreshToken(for: overlayAsset.id).uuidString,
            ].joined(separator: "|")
        )
    }

    private var focusThumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(state.comparePaneAssets.enumerated()), id: \.offset) { index, optionalAsset in
                    if let asset = optionalAsset {
                        let isFocused = asset.id == state.compareFocusedAsset?.id

                        Button {
                            focusThumbnailScrollPositionID = asset.id
                            state.focusCompareAsset(asset.id)
                            resetActiveTransform()
                            loadTolerancePairsIfVisible()
                        } label: {
                            CompareFocusThumbnailItem(
                                asset: asset,
                                fileURL: state.fileURL(for: asset),
                                refreshToken: state.imageRefreshToken(for: asset.id),
                                index: index + 1,
                                isFocused: isFocused
                            )
                        }
                        .buttonStyle(.plain)
                        .id(asset.id)
                    } else {
                        CompareMissingPane(message: "\(index + 1) · 缺图")
                            .frame(width: 144, height: 126)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 1)
        }
        .scrollPosition(id: $focusThumbnailScrollPositionID, anchor: .center)
        .onAppear {
            focusThumbnailScrollPositionID = state.compareFocusedAsset?.id
        }
        .onChange(of: state.compareFocusedAsset?.id) { _, assetID in
            focusThumbnailScrollPositionID = assetID
        }
    }

    private func resetActiveTransform() {
        compareZoom = 1
        comparePan = .zero
    }

    private func handleCompareWheelZoom(_ request: CompareZoomRequest) {
        guard interactions.wheelZoomEnabled else { return }
        let adjustedRequest = CompareZoomRequest(
            deltaY: interactions.adjustedZoomDelta(request.deltaY),
            anchor: request.anchor,
            containerSize: request.containerSize,
            viewport: request.viewport,
            imageSize: request.imageSize
        )
        let transform = zoomedTransform(
            for: adjustedRequest,
            currentZoom: compareZoom,
            currentPan: comparePan
        )
        compareZoom = transform.zoom
        comparePan = transform.pan
    }

    private func zoomedTransform(
        for request: CompareZoomRequest,
        currentZoom: CGFloat,
        currentPan: CGSize
    ) -> (zoom: CGFloat, pan: CGSize) {
        guard request.deltaY != 0 else {
            return (currentZoom, currentPan)
        }
        let direction: CGFloat = request.deltaY > 0 ? -1 : 1
        let newZoom = min(max(currentZoom + (direction * 0.08), minimumZoom), maximumZoom)
        guard newZoom != currentZoom else {
            return (currentZoom, currentPan)
        }
        guard newZoom > minimumZoom else {
            return (newZoom, .zero)
        }

        let newPan = CompareLayoutMetrics.anchoredNormalizedPan(
            normalizedPan: currentPan,
            from: currentZoom,
            to: newZoom,
            anchor: request.anchor,
            containerSize: request.containerSize,
            imageSize: request.imageSize,
            viewport: request.viewport
        )
        return (newZoom, newPan)
    }

    private func setToleranceThreshold(_ value: Int) {
        let clamped = min(max(value, 0), 255)
        toleranceSliderValue = Double(clamped)
        guard clamped != toleranceThreshold else { return }
        toleranceThreshold = clamped
        loadTolerancePairsIfVisible(debounce: true)
    }

    private func toleranceResizeHandle(
        currentHeight: CGFloat,
        containerHeight: CGFloat,
        reservedUpperHeight: CGFloat
    ) -> some View {
        CompareToleranceResizeHandle(
            onResize: { translation in
                let startHeight = toleranceResizeStartHeight ?? currentHeight
                if toleranceResizeStartHeight == nil {
                    toleranceResizeStartHeight = startHeight
                }
                tolerancePanelHeight = CompareLayoutMetrics.clampedToleranceHeight(
                    proposedHeight: startHeight - translation,
                    containerHeight: containerHeight,
                    reservedUpperHeight: reservedUpperHeight
                )
            },
            onResizeEnd: {
                toleranceResizeStartHeight = nil
            },
            onNudge: { delta in
                tolerancePanelHeight = CompareLayoutMetrics.clampedToleranceHeight(
                    proposedHeight: (tolerancePanelHeight ?? currentHeight) + delta,
                    containerHeight: containerHeight,
                    reservedUpperHeight: reservedUpperHeight
                )
            }
        )
    }

    private func handleKeyDown(_ input: KeyInput) -> Bool {
        guard state.mode == .compare else { return false }

        if let paneIndex = ComparePaneRotationShortcut.index(for: input, shortcuts: shortcuts.map) {
            guard let assetID = state.compareAsset(atPane: paneIndex)?.id else { return true }
            Task {
                await state.rotateLocalAssetFiles([assetID], quarterTurns: 1)
                resetActiveTransform()
                loadTolerancePairsIfVisible()
            }
            return true
        }

        // Command + number applies a P tag to the whole compare selection.
        // Option + Command + number applies it only to the image currently
        // under the pointer, so moving the mouse changes the target directly.
        if let priorityTag = CompareSingleImagePriorityShortcut.tag(for: input) {
            guard !input.isRepeat else { return true }
            guard let targetAssetID = hoveredCompareAssetID else { return true }
            guard state.priorityTags.contains(priorityTag) else { return true }
            state.applyPriorityTag(priorityTag, to: [targetAssetID])
            return true
        }

        let action = CompareKeyboardAction.action(for: input, shortcuts: shortcuts.map)
        switch action {
        case .showOverview:
            if !state.isSingleImageCompareMode, !state.isShowingCompareOverview {
                let targetID = state.compareFocusedAsset?.id
                state.showCompareOverview()
                resetActiveTransform()
                requestOverviewScroll(to: targetID)
                loadTolerancePairsIfVisible()
            }
        case .rateKeep:
            applyRatingToCompareSelection(.keep)
        case .ratePending:
            applyRatingToCompareSelection(.pending)
        case .rateReject:
            applyRatingToCompareSelection(.reject)
        case .clearAllTags:
            clearAllTagsFromCompareSelection()
        case let .applyPriorityTag(priorityTag):
            guard state.priorityTags.contains(priorityTag) else { return true }
            guard !input.isRepeat else { return true }
            applyPriorityTagToCompareSelection(priorityTag)
        case .previousGroup:
            stepCompareGroup(delta: -1)
        case .nextGroup:
            stepCompareGroup(delta: 1)
        case .beginCyclicOverlay:
            setCyclicOverlayActive(true)
        case .toggleToleranceView:
            if state.compareAssets.count >= 2 {
                isToleranceViewVisible.toggle()
                loadTolerancePairsIfVisible()
            }
        case .rotateFocusedClockwise:
            state.rotateFocusedAsset(quarterTurns: 1)
            resetActiveTransform()
            loadTolerancePairsIfVisible()
        case .rotateFocusedCounterclockwise:
            state.rotateFocusedAsset(quarterTurns: -1)
            resetActiveTransform()
            loadTolerancePairsIfVisible()
        case .rotateSelectionClockwise:
            state.rotateCompareSelection(quarterTurns: 1)
            resetActiveTransform()
            loadTolerancePairsIfVisible()
        case .rotateSelectionCounterclockwise:
            state.rotateCompareSelection(quarterTurns: -1)
            resetActiveTransform()
            loadTolerancePairsIfVisible()
        case let .numberedOverlay(slot):
            state.setBaseCompareOverlay(slot: slot)
            loadTolerancePairsIfVisible()
        case .none:
            break
        }
        return action != .none
    }

    private func handleKeyUp(_ input: KeyInput) {
        if CompareKeyboardAction.action(for: input, shortcuts: shortcuts.map) == .beginCyclicOverlay {
            setCyclicOverlayActive(false)
        }
    }

    private func setCyclicOverlayActive(_ isActive: Bool) {
        guard CompareCyclicOverlayBehavior.shouldApplyStateChange(
            currentValue: isCyclicOverlayActive,
            requestedValue: isActive,
            assetCount: state.compareAssets.count
        ) else {
            return
        }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isCyclicOverlayActive = isActive
        }

        // Overview tolerance pairs already use the same cyclic order, so Q
        // should not restart those render jobs. Detail tolerance changes pair.
        if isToleranceViewVisible, !state.isShowingCompareOverview {
            loadTolerancePairsIfVisible()
        }
    }

    private func stepCompareGroup(delta: Int) {
        if state.stepBasenameCompareGroup(delta: delta) {
            resetActiveTransform()
            requestOverviewScroll(to: state.compareSelectionIDs.first)
            loadTolerancePairsIfVisible()
        }
    }

    private func loadTolerancePairsIfVisible(
        blueDifferencesVisible: Bool? = nil,
        debounce: Bool = false
    ) {
#if canImport(AppKit)
        guard isToleranceViewVisible else { return }
        let shouldShowBlueDifferences = blueDifferencesVisible ?? showsSubToleranceDifferences
        var pairs = overviewTolerancePairs
        if let detailPair = detailTolerancePair,
           !pairs.contains(where: { $0.id == detailPair.id }) {
            pairs.append(detailPair)
        }
        toleranceStore.load(
            pairs: pairs,
            tolerance: toleranceThreshold,
            showsSubToleranceDifferences: shouldShowBlueDifferences,
            debounce: debounce
        )
#endif
    }

    private func requestOverviewScroll(to assetID: UUID?) {
        guard let assetID else { return }
        overviewScrollPositionID = assetID
        overviewScrollTargetID = assetID
    }

    private func scrollOverviewIfNeeded(_ proxy: ScrollViewProxy) {
        guard let overviewScrollTargetID else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.16)) {
                proxy.scrollTo(overviewScrollTargetID, anchor: .center)
            }
        }
    }

    private func applyRatingToCompareSelection(_ rating: RatingState) {
        let assetIDs = state.compareSelectionIDs
        guard !assetIDs.isEmpty else { return }
        state.applyRating(rating, to: assetIDs)
    }

    private func applyPriorityTagToCompareSelection(_ priorityTag: PriorityTag) {
        let assetIDs = state.compareSelectionIDs
        guard !assetIDs.isEmpty else { return }
        state.applyPriorityTag(priorityTag, to: assetIDs)
    }

    private func clearAllTagsFromCompareSelection() {
        let assetIDs = state.compareSelectionIDs
        guard !assetIDs.isEmpty else { return }
        state.clearAllTriageTags(from: assetIDs)
    }

    private func overlayAction(for slot: Int) -> KeyboardShortcutAction {
        switch slot {
        case 1:
            return .overlay1
        case 2:
            return .overlay2
        case 3:
            return .overlay3
        case 4:
            return .overlay4
        case 5:
            return .overlay5
        case 6:
            return .overlay6
        case 7:
            return .overlay7
        case 8:
            return .overlay8
        default:
            return .overlay9
        }
    }

    private func saveCompareGIF(_ request: CompareGIFExportRequest) {
#if canImport(AppKit)
        let items = state.compareAssets.compactMap { asset -> CompareGIFExportItem? in
            guard let fileURL = state.fileURL(for: asset) else { return nil }
            return CompareGIFExportItem(asset: asset, fileURL: fileURL)
        }
        CompareGIFExporter.saveWithPanel(items: items, request: request)
#endif
    }
}

private struct CompareOverlayShortcutButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let size = CompareLayoutMetrics.overlayShortcutItemSize()

        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .background(background(configuration: configuration), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed ? AppButtonTokens.pressedScale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        isSelected ? AppTheme.textOnAccent : AppTheme.textPrimary
    }

    private func background(configuration: Configuration) -> AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        AppTheme.accentLime.opacity(configuration.isPressed ? 0.86 : 1),
                        Color(red: 0.760, green: 0.900, blue: 0.205).opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    AppTheme.textPrimary.opacity(configuration.isPressed ? 0.070 : 0.055),
                    AppTheme.textPrimary.opacity(0.030)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var borderColor: Color {
        isSelected ? AppTheme.textOnAccent.opacity(0.12) : AppTheme.borderSoft.opacity(0.75)
    }
}

private struct CompareFocusThumbnailItem: View {
    let asset: AssetRecord
    let fileURL: URL?
    let refreshToken: UUID
    let index: Int
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topLeading) {
                CompareAssetImage(
                    asset: asset,
                    fileURL: fileURL,
                    refreshToken: refreshToken,
                    maxPixelSize: 900,
                    contentMode: .fill
                )
                .frame(width: 126, height: 72)
                .clipped()

                Text("#\(index)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(asset.filename)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 126, alignment: .leading)

            Text(asset.relativePath)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.50))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 126, alignment: .leading)
        }
        .padding(8)
        .frame(width: 144, height: 126, alignment: .topLeading)
        .background(isFocused ? ComparePalette.selectedPanel : ComparePalette.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(isFocused ? ComparePalette.accent : .clear)
                .frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isFocused ? ComparePalette.accent.opacity(0.65) : ComparePalette.separator, lineWidth: 1)
        }
    }
}

enum CompareSingleImagePriorityShortcut {
    static func tag(for input: KeyInput) -> PriorityTag? {
        guard input.isCommandPressed,
              input.isOptionPressed,
              !input.isShiftPressed,
              !input.isControlPressed,
              let number = input.numberKey else {
            return nil
        }

        return PriorityTag(index: number == 0 ? 9 : number - 1)
    }
}

enum CompareKeyboardAction: Equatable {
    case showOverview
    case rateKeep
    case ratePending
    case rateReject
    case clearAllTags
    case applyPriorityTag(PriorityTag)
    case previousGroup
    case nextGroup
    case beginCyclicOverlay
    case toggleToleranceView
    case rotateFocusedClockwise
    case rotateFocusedCounterclockwise
    case rotateSelectionClockwise
    case rotateSelectionCounterclockwise
    case numberedOverlay(Int)
    case none

    static func action(for key: String, shortcuts: KeyboardShortcutMap = .default) -> CompareKeyboardAction {
        guard let input = KeyInput(characters: key) else { return .none }
        return action(for: input, shortcuts: shortcuts)
    }

    static func action(for input: KeyInput, shortcuts: KeyboardShortcutMap = .default) -> CompareKeyboardAction {
        switch shortcuts.action(for: input, scope: .compare) {
        case .some(.keep):
            return .rateKeep
        case .some(.pending):
            return .ratePending
        case .some(.reject):
            return .rateReject
        case .some(.clearAllTags):
            return .clearAllTags
        case .some(let action) where action.priorityTag != nil:
            return action.priorityTag.map(CompareKeyboardAction.applyPriorityTag) ?? .none
        case .some(let action) where action.isCyclicOverlay:
            return .beginCyclicOverlay
        case .some(let action) where action.isToleranceView:
            return .toggleToleranceView
        case .some(let action) where action.isPreviousGroup:
            return .previousGroup
        case .some(.previousGroupArrow):
            return .previousGroup
        case .some(.nextGroup), .some(.nextGroupArrow):
            return .nextGroup
        case .some(.showOverview):
            return .showOverview
        case .some(let action) where action.overlaySlot != nil:
            return action.overlaySlot.map(CompareKeyboardAction.numberedOverlay) ?? .none
        case .some(.rotateFocusedCounterclockwise):
            return .rotateFocusedCounterclockwise
        case .some(.rotateSelectionClockwise):
            return .rotateSelectionClockwise
        case .some(.rotateSelectionCounterclockwise):
            return .rotateSelectionCounterclockwise
        default:
            return .none
        }
    }
}

enum ComparePaneRotationShortcut {
    static func index(
        for input: KeyInput,
        shortcuts: KeyboardShortcutMap = .default
    ) -> Int? {
        shortcuts.action(for: input, scope: .compare)?.rotatePaneSlot.map { $0 - 1 }
    }
}

private enum ComparePalette {
    static let canvas = LinearGradient(
        colors: [
            Color(nsColor: NSColor(calibratedWhite: 0.045, alpha: 1)),
            Color(nsColor: NSColor(calibratedWhite: 0.075, alpha: 1))
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let panel = Color(nsColor: NSColor(calibratedWhite: 0.095, alpha: 1))
    static let selectedPanel = Color(nsColor: NSColor(calibratedWhite: 0.16, alpha: 1))
    static let stage = Color(nsColor: NSColor(calibratedWhite: 0.035, alpha: 1))
    static let separator = Color.white.opacity(0.055)
    static let accent = Color.accentColor
}

private struct CompareOverviewPane: View {
    let asset: AssetRecord
    let fileURL: URL?
    let overlayAsset: AssetRecord?
    let overlayFileURL: URL?
    let overlayIsVisible: Bool
    let refreshToken: UUID
    let overlayRefreshToken: UUID?
    let index: Int
    let total: Int
    let floatingBadge: String?
    let zoomScale: CGFloat
    @Binding var pan: CGSize
    var showsOverlayMarks = true
    let onActivate: () -> Void
    let onZoom: (CompareZoomRequest) -> Void
    let onRevealInFinder: (() -> Void)?
    let onApplyRating: (RatingState) -> Void
    let onApplyPriorityTag: (PriorityTag) -> Void
    let onClearPriorityTag: () -> Void
    let onClearAllTags: () -> Void
    let onSaveGIF: (CompareGIFExportRequest) -> Void
    let onHoverAsset: (UUID?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ComparePaneHeader(
                subtitle: "(\(index)/\(total))  \(asset.relativePath)"
            )

            ComparePannableViewport(
                asset: asset,
                fileURL: fileURL,
                overlayAsset: overlayAsset,
                overlayFileURL: overlayFileURL,
                overlayIsVisible: overlayIsVisible,
                refreshToken: refreshToken,
                overlayRefreshToken: overlayRefreshToken,
                zoomScale: zoomScale,
                pan: $pan,
                contentInset: 0,
                showsOverlayMarks: showsOverlayMarks,
                floatingBadge: floatingBadge,
                onZoom: onZoom,
                onRevealInFinder: onRevealInFinder,
                onApplyRating: onApplyRating,
                onApplyPriorityTag: onApplyPriorityTag,
                onClearPriorityTag: onClearPriorityTag,
                onClearAllTags: onClearAllTags,
                onSaveGIF: onSaveGIF,
                onHoverAsset: onHoverAsset
            )
        }
        .background(ComparePalette.panel)
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
    }
}

private struct CompareMissingPane: View {
    var subtitle: String? = nil
    var message = "缺少同名文件"

    var body: some View {
        VStack(spacing: 0) {
            if let subtitle {
                ComparePaneHeader(subtitle: subtitle)
            }
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 26))
                Text(message)
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.42))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
            }
            .padding(12)
        }
        .background(ComparePalette.stage)
        .accessibilityElement(children: .combine)
    }
}

private struct ComparePaneHeader: View {
    let subtitle: String

    var body: some View {
        HStack(spacing: 8) {
            Text(subtitle)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.62))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.black.opacity(0.22))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ComparePalette.separator)
                .frame(height: 1)
        }
    }
}

private struct ComparePairBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
            .colorScheme(.dark)
    }
}

private struct ComparePannableViewport: View {
    @EnvironmentObject private var shortcuts: KeyboardShortcutStore
    @Environment(\.displayScale) private var displayScale

    let asset: AssetRecord
    let fileURL: URL?
    var overlayAsset: AssetRecord? = nil
    var overlayFileURL: URL? = nil
    var overlayIsVisible = true
    var instantOverlayAsset: AssetRecord? = nil
    var instantOverlayFileURL: URL? = nil
    var instantOverlayIsVisible = false
    var refreshToken: UUID? = nil
    var overlayRefreshToken: UUID? = nil
    var instantOverlayRefreshToken: UUID? = nil
    let zoomScale: CGFloat
    @Binding var pan: CGSize
    let contentInset: CGFloat
    var locksOverlayToBaseGeometry = false
    var showsOverlayMarks = true
    var floatingBadge: String? = nil
    let onZoom: (CompareZoomRequest) -> Void
    let onRevealInFinder: (() -> Void)?
    let onApplyRating: (RatingState) -> Void
    let onApplyPriorityTag: (PriorityTag) -> Void
    let onClearPriorityTag: () -> Void
    let onClearAllTags: () -> Void
    let onSaveGIF: (CompareGIFExportRequest) -> Void
    let onHoverAsset: (UUID?) -> Void

    @State private var isDragging = false
    @State private var isHovering = false
    @State private var panCursorActive = false

    var body: some View {
        GeometryReader { proxy in
            let viewport = CGSize(
                width: max(proxy.size.width - (contentInset * 2), 1),
                height: max(proxy.size.height - (contentInset * 2), 1)
            )
            let contentSize = CompareLayoutMetrics.fittedImageSize(
                imageSize: asset.pixelSize,
                viewport: viewport,
                zoomScale: zoomScale
            )
            let renderPixelDimension = CompareLayoutMetrics.requiredRenderPixelDimension(
                originalPixelSize: asset.pixelSize,
                renderedPointSize: contentSize,
                displayScale: displayScale
            )
            let panContentSize = CompareLayoutMetrics.pannableContentSize(
                fittedContentSize: contentSize,
                viewport: viewport,
                zoomScale: zoomScale
            )
            let actualOffset = CompareLayoutMetrics.actualPanOffset(
                normalizedPan: pan,
                viewport: viewport,
                contentSize: panContentSize
            )
            let overlayContentSize = overlayAsset.map {
                CompareLayoutMetrics.overlayContentSize(
                    baseContentSize: contentSize,
                    overlayContentSize: CompareLayoutMetrics.fittedImageSize(
                        imageSize: $0.pixelSize,
                        viewport: viewport,
                        zoomScale: zoomScale
                    ),
                    lockToBaseGeometry: locksOverlayToBaseGeometry
                )
            }
            let overlayRenderPixelDimension = overlayAsset.flatMap { overlayAsset in
                overlayContentSize.map { overlayContentSize in
                    CompareLayoutMetrics.requiredRenderPixelDimension(
                        originalPixelSize: overlayAsset.pixelSize,
                        renderedPointSize: overlayContentSize,
                        displayScale: displayScale
                    )
                }
            }
            let instantOverlayContentSize = instantOverlayAsset.map {
                CompareLayoutMetrics.overlayContentSize(
                    baseContentSize: contentSize,
                    overlayContentSize: CompareLayoutMetrics.fittedImageSize(
                        imageSize: $0.pixelSize,
                        viewport: viewport,
                        zoomScale: zoomScale
                    ),
                    lockToBaseGeometry: locksOverlayToBaseGeometry
                )
            }
            let instantOverlayRenderPixelDimension = instantOverlayAsset.flatMap { instantOverlayAsset in
                instantOverlayContentSize.map { instantOverlayContentSize in
                    CompareLayoutMetrics.requiredRenderPixelDimension(
                        originalPixelSize: instantOverlayAsset.pixelSize,
                        renderedPointSize: instantOverlayContentSize,
                        displayScale: displayScale
                    )
                }
            }

            ZStack {
                ComparePalette.stage

                CompareAssetImage(
                    asset: asset,
                    fileURL: fileURL,
                    refreshToken: refreshToken,
                    maxPixelSize: renderPixelDimension,
                    contentMode: .fit
                )
                    .frame(width: contentSize.width, height: contentSize.height)
                    .position(
                        x: (proxy.size.width * 0.5) + actualOffset.width,
                        y: (proxy.size.height * 0.5) + actualOffset.height
                    )
                    .allowsHitTesting(false)

                if let overlayAsset,
                   let overlayFileURL,
                   let overlayContentSize,
                   let overlayRenderPixelDimension {
                    CompareAssetImage(
                        asset: overlayAsset,
                        fileURL: overlayFileURL,
                        refreshToken: overlayRefreshToken,
                        maxPixelSize: overlayRenderPixelDimension,
                        contentMode: .fit,
                        locksToBounds: locksOverlayToBaseGeometry,
                        showsLoadingIndicator: false
                    )
                        .frame(width: overlayContentSize.width, height: overlayContentSize.height)
                        .position(
                            x: (proxy.size.width * 0.5) + actualOffset.width,
                            y: (proxy.size.height * 0.5) + actualOffset.height
                        )
                        .opacity(overlayIsVisible ? CompareLayoutMetrics.overlayOpacity : 0)
                        .blendMode(.normal)
                        .allowsHitTesting(false)
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                }

                if let instantOverlayAsset,
                   let instantOverlayFileURL,
                   let instantOverlayContentSize,
                   let instantOverlayRenderPixelDimension {
                    CompareAssetImage(
                        asset: instantOverlayAsset,
                        fileURL: instantOverlayFileURL,
                        refreshToken: instantOverlayRefreshToken,
                        maxPixelSize: instantOverlayRenderPixelDimension,
                        contentMode: .fit,
                        locksToBounds: locksOverlayToBaseGeometry,
                        showsLoadingIndicator: false
                    )
                        .frame(width: instantOverlayContentSize.width, height: instantOverlayContentSize.height)
                        .position(
                            x: (proxy.size.width * 0.5) + actualOffset.width,
                            y: (proxy.size.height * 0.5) + actualOffset.height
                        )
                        .opacity(instantOverlayIsVisible ? CompareLayoutMetrics.overlayOpacity : 0)
                        .blendMode(.normal)
                        .allowsHitTesting(false)
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                onHoverAsset(hovering ? asset.id : nil)
                updatePanCursor()
            }
            .onChange(of: isDragging) { _, _ in
                updatePanCursor()
            }
            .onChange(of: zoomScale) { _, _ in
                updatePanCursor()
            }
            .onDisappear {
                onHoverAsset(nil)
                clearPanCursorIfNeeded()
            }
            .overlay {
                ScrollWheelZoomMonitor { event in
                    onZoom(
                        CompareZoomRequest(
                            deltaY: event.deltaY,
                            anchor: event.location,
                            containerSize: proxy.size,
                            viewport: viewport,
                            imageSize: asset.pixelSize
                        )
                    )
                }
            }
            .overlay(alignment: .topLeading) {
                CompareAssetMarksHUD(asset: asset)
                    .padding(contentInset + 14)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                if showsOverlayMarks, let overlayAsset {
                    CompareAssetMarksHUD(asset: overlayAsset, prefix: "叠图")
                        .padding(contentInset + 14)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let floatingBadge {
                    ComparePairBadge(text: floatingBadge)
                        .padding(contentInset + 10)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
#if canImport(AppKit)
                CompareDragSurface(
                    pan: $pan,
                    hoveredAssetID: asset.id,
                    viewport: viewport,
                    contentSize: panContentSize,
                    shortcutMap: shortcuts.map,
                    onDraggingChanged: { dragging in
                        isDragging = dragging
                    },
                    onRevealInFinder: onRevealInFinder,
                    onApplyRating: onApplyRating,
                    onApplyPriorityTag: onApplyPriorityTag,
                    onClearPriorityTag: onClearPriorityTag,
                    onClearAllTags: onClearAllTags,
                    onSaveGIF: { displayScale in
                        onSaveGIF(
                            CompareGIFExportRequest(
                                viewport: viewport,
                                zoomScale: zoomScale,
                                pan: pan,
                                contentInset: contentInset,
                                displayScale: displayScale
                            )
                        )
                    },
                    onHoverAsset: onHoverAsset
                )
#endif
            }
        }
    }

#if canImport(AppKit)
    private func clearPanCursorIfNeeded() {
        if panCursorActive {
            NSCursor.pop()
            panCursorActive = false
        }
    }

    private func updatePanCursor() {
        let shouldShowCursor = isHovering
        if !shouldShowCursor {
            if panCursorActive {
                NSCursor.pop()
                panCursorActive = false
            }
            return
        }

        if panCursorActive {
            NSCursor.pop()
        }
        (isDragging ? NSCursor.closedHand : NSCursor.openHand).push()
        panCursorActive = true
    }
#endif
}

private struct CompareAssetMarksHUD: View {
    let asset: AssetRecord
    var prefix: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                if let prefix {
                    AppStatusPill(prefix, status: .focused)
                }
                RatingBadge(rating: asset.ratingState)
            }

            ForEach(asset.appTags.prefix(4)) { tag in
                TagPill(tag: tag)
                    .frame(maxWidth: 220, alignment: .leading)
            }
        }
        .padding(10)
        .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .colorScheme(.dark)
    }

}

#if canImport(AppKit)
struct CompareDragSurface: NSViewRepresentable {
    @EnvironmentObject private var state: AppState
    @Binding var pan: CGSize
    var hoveredAssetID: UUID? = nil
    let viewport: CGSize
    let contentSize: CGSize
    var shortcutMap: KeyboardShortcutMap = .default
    var allowsContextMenu = true
    let onDraggingChanged: (Bool) -> Void
    let onRevealInFinder: (() -> Void)?
    let onApplyRating: (RatingState) -> Void
    let onApplyPriorityTag: (PriorityTag) -> Void
    let onClearPriorityTag: () -> Void
    let onClearAllTags: () -> Void
    let onSaveGIF: (CGFloat) -> Void
    var onHoverAsset: (UUID?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(pan: $pan)
    }

    func makeNSView(context: Context) -> CompareDragSurfaceView {
        let view = CompareDragSurfaceView(frame: .zero)
        view.allowsContextMenu = allowsContextMenu
        view.shortcutMap = shortcutMap
        view.priorityTagDefinitions = state.priorityTagDefinitions
        view.onRevealInFinder = onRevealInFinder
        view.onApplyRating = onApplyRating
        view.onApplyPriorityTag = onApplyPriorityTag
        view.onClearPriorityTag = onClearPriorityTag
        view.onClearAllTags = onClearAllTags
        view.onEditPriorityTags = { window in
            PriorityTagEditorPresenter.present(state: state, in: window)
        }
        view.onAddPriorityTag = { window in
            PriorityTagEditorPresenter.present(state: state, in: window, addingTag: true)
        }
        view.onSaveGIF = onSaveGIF
        view.hoveredAssetID = hoveredAssetID
        view.onHoverAsset = onHoverAsset
        view.onMouseDown = { event in
            context.coordinator.beginDrag(
                at: event.locationInWindow,
                viewport: viewport,
                contentSize: contentSize
            )
            onDraggingChanged(true)
        }
        view.onMouseDragged = { event in
            context.coordinator.updateDrag(
                to: event.locationInWindow,
                viewport: viewport,
                contentSize: contentSize
            )
        }
        view.onMouseUp = { event in
            context.coordinator.updateDrag(
                to: event.locationInWindow,
                viewport: viewport,
                contentSize: contentSize
            )
            context.coordinator.endDrag()
            onDraggingChanged(false)
        }
        return view
    }

    func updateNSView(_ nsView: CompareDragSurfaceView, context: Context) {
        context.coordinator.pan = $pan
        nsView.allowsContextMenu = allowsContextMenu
        nsView.shortcutMap = shortcutMap
        nsView.priorityTagDefinitions = state.priorityTagDefinitions
        nsView.onRevealInFinder = onRevealInFinder
        nsView.onApplyRating = onApplyRating
        nsView.onApplyPriorityTag = onApplyPriorityTag
        nsView.onClearPriorityTag = onClearPriorityTag
        nsView.onClearAllTags = onClearAllTags
        nsView.onEditPriorityTags = { window in
            PriorityTagEditorPresenter.present(state: state, in: window)
        }
        nsView.onAddPriorityTag = { window in
            PriorityTagEditorPresenter.present(state: state, in: window, addingTag: true)
        }
        nsView.onSaveGIF = onSaveGIF
        nsView.hoveredAssetID = hoveredAssetID
        nsView.onHoverAsset = onHoverAsset
        nsView.onMouseDown = { event in
            context.coordinator.beginDrag(
                at: event.locationInWindow,
                viewport: viewport,
                contentSize: contentSize
            )
            onDraggingChanged(true)
        }
        nsView.onMouseDragged = { event in
            context.coordinator.updateDrag(
                to: event.locationInWindow,
                viewport: viewport,
                contentSize: contentSize
            )
        }
        nsView.onMouseUp = { event in
            context.coordinator.updateDrag(
                to: event.locationInWindow,
                viewport: viewport,
                contentSize: contentSize
            )
            context.coordinator.endDrag()
            onDraggingChanged(false)
        }
    }

    @MainActor
    final class Coordinator {
        var pan: Binding<CGSize>
        private var dragStartPan: CGSize = .zero
        private var dragStartPoint: CGPoint = .zero
        private var isDragging = false

        init(pan: Binding<CGSize>) {
            self.pan = pan
        }

        func beginDrag(at point: CGPoint, viewport: CGSize, contentSize: CGSize) {
            dragStartPan = pan.wrappedValue
            dragStartPoint = point
            isDragging = true
        }

        func updateDrag(to point: CGPoint, viewport: CGSize, contentSize: CGSize) {
            guard isDragging else { return }
            let translation = CGSize(
                width: point.x - dragStartPoint.x,
                height: dragStartPoint.y - point.y
            )
            pan.wrappedValue = CompareLayoutMetrics.normalizedPan(
                start: dragStartPan,
                translation: translation,
                viewport: viewport,
                contentSize: contentSize
            )
        }

        func endDrag() {
            dragStartPan = pan.wrappedValue
            isDragging = false
        }
    }
}

final class CompareDragSurfaceView: NSView {
    var allowsContextMenu = true
    var shortcutMap: KeyboardShortcutMap = .default
    var hoveredAssetID: UUID?
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseDragged: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onRevealInFinder: (() -> Void)?
    var onApplyRating: ((RatingState) -> Void)?
    var onApplyPriorityTag: ((PriorityTag) -> Void)?
    var priorityTagDefinitions: [PriorityTagDefinition] = PriorityTagDefinition.defaults
    var onClearPriorityTag: (() -> Void)?
    var onClearAllTags: (() -> Void)?
    var onEditPriorityTags: ((NSWindow?) -> Void)?
    var onAddPriorityTag: ((NSWindow?) -> Void)?
    var onSaveGIF: ((CGFloat) -> Void)?
    var onHoverAsset: ((UUID?) -> Void)?

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverAsset?(hoveredAssetID)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverAsset?(nil)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: NSCursor.openHand)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        NSCursor.closedHand.push()
        onMouseDown?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(event)
        NSCursor.pop()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard allowsContextMenu else { return }
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
    }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(actionMenuItem(title: "在 Finder 中显示此图片", action: #selector(revealInFinder), isEnabled: onRevealInFinder != nil))
        menu.addItem(actionMenuItem(title: "保存 GIF（无限循环）", action: #selector(saveGIF), isEnabled: onSaveGIF != nil))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(ratingMenuItem(title: shortcutTitle("保留", action: .keep), action: #selector(markKeep)))
        menu.addItem(ratingMenuItem(title: shortcutTitle("恢复", action: .pending), action: #selector(markPending)))
        menu.addItem(ratingMenuItem(title: shortcutTitle("淘汰", action: .reject), action: #selector(markReject)))
        menu.addItem(NSMenuItem.separator())
        for definition in priorityTagDefinitions {
            let action = KeyboardShortcutAction.allCases.first { $0.priorityTag == definition.tag }
            let title = action.map { shortcutTitle(definition.name, action: $0) } ?? definition.name
            let item = ratingMenuItem(title: title, action: #selector(markPriorityTag(_:)))
            item.representedObject = definition.tag.rawValue
            menu.addItem(item)
        }
        menu.addItem(ratingMenuItem(title: "清除 P 标签", action: #selector(clearPriorityTag)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(actionMenuItem(title: "编辑 P 标签名称…", action: #selector(editPriorityTags), isEnabled: onEditPriorityTags != nil))
        menu.addItem(actionMenuItem(title: "新增 P 标签…", action: #selector(addPriorityTag), isEnabled: onAddPriorityTag != nil))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(ratingMenuItem(title: shortcutTitle("清除选中标签", action: .clearAllTags), action: #selector(clearAllTags)))
        return menu
    }

    private func shortcutTitle(_ title: String, action: KeyboardShortcutAction) -> String {
        if let priorityTag = action.priorityTag {
            let number = priorityTag.index == 9 ? 0 : priorityTag.index + 1
            return "\(title)（⌥⌘\(number)）"
        }
        return "\(title)（\(shortcutMap.displayKey(for: action))）"
    }

    private func actionMenuItem(title: String, action: Selector, isEnabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        return item
    }

    private func ratingMenuItem(title: String, action: Selector) -> NSMenuItem {
        actionMenuItem(title: title, action: action)
    }

    @objc private func revealInFinder() {
        onRevealInFinder?()
    }

    @objc private func saveGIF() {
        onSaveGIF?(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
    }

    @objc private func editPriorityTags() {
        onEditPriorityTags?(window)
    }

    @objc private func addPriorityTag() {
        onAddPriorityTag?(window)
    }

    @objc private func markKeep() {
        onApplyRating?(.keep)
    }

    @objc private func markReject() {
        onApplyRating?(.reject)
    }

    @objc private func markPending() {
        onApplyRating?(.pending)
    }

    @objc private func markPriorityTag(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let tag = PriorityTag(rawValue: value) else { return }
        onApplyPriorityTag?(tag)
    }

    @objc private func clearPriorityTag() {
        onClearPriorityTag?()
    }

    @objc private func clearAllTags() {
        onClearAllTags?()
    }
}
#endif

private struct CompareDetailStage: View {
    let focusedAsset: AssetRecord
    let focusedFileURL: URL?
    let overlayAsset: AssetRecord?
    let overlayFileURL: URL?
    let overlayIsVisible: Bool
    let instantOverlayAsset: AssetRecord?
    let instantOverlayFileURL: URL?
    let instantOverlayIsVisible: Bool
    let refreshToken: UUID
    let overlayRefreshToken: UUID?
    let instantOverlayRefreshToken: UUID?
    let zoomScale: CGFloat
    @Binding var pan: CGSize
    let locksOverlayToBaseGeometry: Bool
    let showsOverlayMarks: Bool
    let floatingBadge: String?
    let onZoom: (CompareZoomRequest) -> Void
    let onRevealInFinder: (() -> Void)?
    let onApplyRating: (RatingState) -> Void
    let onApplyPriorityTag: (PriorityTag) -> Void
    let onClearPriorityTag: () -> Void
    let onClearAllTags: () -> Void
    let onSaveGIF: (CompareGIFExportRequest) -> Void
    let onHoverAsset: (UUID?) -> Void

    private let contentInset: CGFloat = 30

    var body: some View {
        ComparePannableViewport(
            asset: focusedAsset,
            fileURL: focusedFileURL,
            overlayAsset: overlayAsset,
            overlayFileURL: overlayFileURL,
            overlayIsVisible: overlayIsVisible,
            instantOverlayAsset: instantOverlayAsset,
            instantOverlayFileURL: instantOverlayFileURL,
            instantOverlayIsVisible: instantOverlayIsVisible,
            refreshToken: refreshToken,
            overlayRefreshToken: overlayRefreshToken,
            instantOverlayRefreshToken: instantOverlayRefreshToken,
            zoomScale: zoomScale,
            pan: $pan,
            contentInset: contentInset,
            locksOverlayToBaseGeometry: locksOverlayToBaseGeometry,
            showsOverlayMarks: showsOverlayMarks,
            floatingBadge: floatingBadge,
            onZoom: onZoom,
            onRevealInFinder: onRevealInFinder,
            onApplyRating: onApplyRating,
            onApplyPriorityTag: onApplyPriorityTag,
            onClearPriorityTag: onClearPriorityTag,
            onClearAllTags: onClearAllTags,
            onSaveGIF: onSaveGIF,
            onHoverAsset: onHoverAsset
        )
        .overlay {
            Rectangle()
                .strokeBorder(Color.white.opacity(0.03), lineWidth: 1)
                .padding(contentInset)
                .allowsHitTesting(false)
        }
        .background(ComparePalette.stage)
    }
}

private struct CompareAssetImage: View {
    let asset: AssetRecord
    let fileURL: URL?
    var refreshToken: UUID? = nil
    let maxPixelSize: CGFloat
    let contentMode: ContentMode
    var locksToBounds = false
    var showsLoadingIndicator = true

    var body: some View {
#if canImport(AppKit)
        CompareAssetImageRepresentable(
            asset: asset,
            fileURL: fileURL,
            refreshToken: refreshToken,
            maxPixelSize: maxPixelSize,
            contentMode: contentMode,
            locksToBounds: locksToBounds,
            showsLoadingIndicator: showsLoadingIndicator
        )
#else
        Color.white.opacity(0.03)
#endif
    }
}

#if canImport(AppKit)
private struct CompareAssetImageRepresentable: NSViewRepresentable {
    let asset: AssetRecord
    let fileURL: URL?
    let refreshToken: UUID?
    let maxPixelSize: CGFloat
    let contentMode: ContentMode
    let locksToBounds: Bool
    let showsLoadingIndicator: Bool

    func makeNSView(context: Context) -> CompareAssetImageHostView {
        CompareAssetImageHostView()
    }

    func updateNSView(_ nsView: CompareAssetImageHostView, context: Context) {
        nsView.configure(
            asset: asset,
            fileURL: fileURL,
            refreshToken: refreshToken,
            maxPixelSize: maxPixelSize,
            contentMode: contentMode,
            locksToBounds: locksToBounds,
            showsLoadingIndicator: showsLoadingIndicator
        )
    }

    static func dismantleNSView(_ nsView: CompareAssetImageHostView, coordinator: ()) {
        nsView.cancelPendingLoad()
    }
}

final class CompareAssetImageHostView: NSView {
    typealias ImageLoader = @MainActor (URL, CGFloat, PhotoImageCachePolicy) async -> NSImage?
    private let imageLoader: ImageLoader
    var displayedImage: NSImage? { imageView.image }
    private let imageView: CompareAspectImageView
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private var representedKey = ""
    // A requested key is not necessarily the frame on screen. In particular,
    // detaching a retained Q layer cancels its request but can leave an old frame.
    private var completedKey: String?
    private var representedSourceKey = ""
    private var representedRefreshToken: UUID?
    private var loadToken = UUID()
    private var imageLoadTask: Task<Void, Never>?
    private var hasImage = false
    private var reconfigureAfterAttachment: (() -> Void)?

    override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, imageLoader: { url, size, policy in
            await PhotoImagePipeline.loadImage(for: url, maxPixelSize: size, cachePolicy: policy)
        })
    }

    init(
        frame frameRect: NSRect,
        imageRenderer: CompareAspectImageView = CompareAspectImageView(),
        imageLoader: @escaping ImageLoader
    ) {
        self.imageLoader = imageLoader
        self.imageView = imageRenderer
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor

        imageView.translatesAutoresizingMaskIntoConstraints = false

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .regular

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.72)
        titleLabel.lineBreakMode = .byTruncatingMiddle

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.82)
        statusLabel.lineBreakMode = .byTruncatingMiddle

        addSubview(imageView)
        addSubview(spinner)
        addSubview(statusLabel)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.82),
            titleLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.82)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        asset: AssetRecord,
        fileURL: URL?,
        refreshToken: UUID?,
        maxPixelSize: CGFloat,
        contentMode: ContentMode,
        locksToBounds: Bool,
        showsLoadingIndicator: Bool
    ) {
        reconfigureAfterAttachment = { [weak self] in
            self?.configure(asset: asset, fileURL: fileURL, refreshToken: refreshToken,
                maxPixelSize: maxPixelSize, contentMode: contentMode,
                locksToBounds: locksToBounds, showsLoadingIndicator: showsLoadingIndicator)
        }
        imageView.contentMode = contentMode
        imageView.locksToBounds = locksToBounds
        imageView.rotationDegrees = asset.normalizedRotationDegrees

        guard let fileURL else {
            imageLoadTask?.cancel()
            imageLoadTask = nil
            completedKey = nil
            loadToken = UUID()
            representedKey = asset.id.uuidString
            showFailure(filename: asset.filename, reason: "路径缺失")
            return
        }

        let requestedMaxPixelSize = max(1, maxPixelSize.rounded(.up))
        let sourceKey = [
            asset.id.uuidString,
            asset.relativePath,
            "\(asset.normalizedRotationDegrees)",
            fileURL.path,
            String(asset.fileSizeBytes),
            String(asset.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0),
            refreshToken?.uuidString ?? "static"
        ].joined(separator: "|")
        let key = [
            sourceKey,
            "\(Int(requestedMaxPixelSize.rounded()))",
            refreshToken?.uuidString ?? "static"
        ].joined(separator: "|")

        if key == representedKey, (hasImage && completedKey == key) || imageLoadTask != nil {
            return
        }
        imageLoadTask?.cancel()
        imageLoadTask = nil

        let shouldBypassCache = !representedKey.isEmpty
            && refreshToken != nil
            && refreshToken != representedRefreshToken

        if !shouldBypassCache,
           let cachedImage = PhotoImagePipeline.cachedImage(
               for: fileURL,
               maxPixelSize: requestedMaxPixelSize,
               fileSizeBytes: asset.fileSizeBytes,
               modificationDate: asset.contentModificationDate
           ) {
            representedKey = key
            representedSourceKey = sourceKey
            representedRefreshToken = refreshToken
            loadToken = UUID()
            completedKey = key
            showImage(cachedImage)
            return
        }


        if !shouldBypassCache,
           let previewImage = PhotoImagePipeline.cachedPreviewImage(
               for: fileURL,
               fileSizeBytes: asset.fileSizeBytes,
               modificationDate: asset.contentModificationDate
           ) {
            representedSourceKey = sourceKey
            showImage(previewImage)
        }

        let keepsCurrentFrameWhileRefreshing = hasImage && representedSourceKey == sourceKey
        completedKey = nil
        representedKey = key
        representedSourceKey = sourceKey
        representedRefreshToken = refreshToken
        if !keepsCurrentFrameWhileRefreshing {
            hasImage = false
        }
        let token = UUID()
        loadToken = token
        if keepsCurrentFrameWhileRefreshing {
            hideLoadingChrome()
        } else if showsLoadingIndicator {
            showLoading(filename: asset.filename)
        } else {
            showSilentLoading()
        }

        let loader = imageLoader
        imageLoadTask = Task { @MainActor [weak self] in
            let image = await loader(fileURL, requestedMaxPixelSize, shouldBypassCache ? .refresh : .readWrite)
            guard !Task.isCancelled, let self, self.loadToken == token, self.representedKey == key else { return }
            self.imageLoadTask = nil
            if let image {
                self.completedKey = key
                self.showImage(image)
            } else {
                self.showFailure(filename: asset.filename, reason: "读取失败")
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelPendingLoad()
        } else {
            reconfigureAfterAttachment?()
        }
    }

    func cancelPendingLoad() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        loadToken = UUID()
    }

    private func showLoading(filename: String) {
        imageView.image = nil
        spinner.isHidden = false
        spinner.startAnimation(nil)
        statusLabel.stringValue = "读取中"
        titleLabel.stringValue = filename
        statusLabel.isHidden = false
        titleLabel.isHidden = false
    }

    private func showSilentLoading() {
        imageView.image = nil
        hideLoadingChrome()
    }

    private func hideLoadingChrome() {
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        statusLabel.isHidden = true
        titleLabel.isHidden = true
    }

    private func showImage(_ image: NSImage) {
        hasImage = true
        imageView.image = image
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        statusLabel.isHidden = true
        titleLabel.isHidden = true
    }

    private func showFailure(filename: String, reason: String) {
        hasImage = false
        imageView.image = nil
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        statusLabel.stringValue = reason
        titleLabel.stringValue = filename
        statusLabel.isHidden = false
        titleLabel.isHidden = false
    }
}

class CompareAspectImageView: NSView {
    var image: NSImage? {
        didSet {
            if oldValue !== image { needsDisplay = true }
        }
    }

    var contentMode: ContentMode = .fit {
        didSet {
            if oldValue != contentMode { needsDisplay = true }
        }
    }

    var locksToBounds = false {
        didSet {
            if oldValue != locksToBounds { needsDisplay = true }
        }
    }

    var rotationDegrees = 0 {
        didSet {
            if oldValue != rotationDegrees { needsDisplay = true }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image else { return }
        let container = CGSize(width: bounds.width, height: bounds.height)
        CompareImageDrawing.draw(
            image,
            rotationDegrees: rotationDegrees,
            container: container,
            contentMode: contentMode,
            locksToBounds: locksToBounds
        )
    }
}

enum CompareImageDrawing {
    static func draw(
        _ image: NSImage,
        rotationDegrees: Int,
        container: CGSize,
        contentMode: ContentMode,
        locksToBounds: Bool
    ) {
        let imageSize = image.size
        let rotation = AssetRecord.normalizedRotationDegrees(rotationDegrees)
        let rotatedImageSize = rotation == 90 || rotation == 270
            ? CGSize(width: imageSize.height, height: imageSize.width)
            : CGSize(width: imageSize.width, height: imageSize.height)
        let drawRect = locksToBounds
            ? CompareLayoutMetrics.imageDrawRectLockedToBounds(container: container)
            : CompareLayoutMetrics.imageDrawRect(
                imageSize: rotatedImageSize,
                container: container,
                contentMode: contentMode
            )

        draw(image, rotationDegrees: rotation, targetRect: drawRect)
    }

    static func draw(
        _ image: NSImage,
        rotationDegrees: Int,
        targetRect: NSRect,
        container: CGSize,
        contentMode: ContentMode,
        locksToBounds: Bool
    ) {
        let rotation = AssetRecord.normalizedRotationDegrees(rotationDegrees)
        let rect = locksToBounds
            ? CompareLayoutMetrics.imageDrawRectLockedToBounds(container: targetRect.size)
                .offsetBy(dx: targetRect.minX, dy: targetRect.minY)
            : targetRect

        draw(image, rotationDegrees: rotation, targetRect: rect)
    }

    private static func draw(_ image: NSImage, rotationDegrees: Int, targetRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: targetRect.midX, y: targetRect.midY)
        context.rotate(by: CGFloat(rotationDegrees) * .pi / 180)

        let targetSize = rotationDegrees == 90 || rotationDegrees == 270
            ? CGSize(width: targetRect.height, height: targetRect.width)
            : CGSize(width: targetRect.width, height: targetRect.height)
        let imageRect = NSRect(
            x: -targetSize.width * 0.5,
            y: -targetSize.height * 0.5,
            width: targetSize.width,
            height: targetSize.height
        )

        image.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.restoreGState()
    }
}
#endif

extension AssetRecord {
    var pixelSize: CGSize {
        guard width > 0, height > 0 else { return .zero }
        if normalizedRotationDegrees == 90 || normalizedRotationDegrees == 270 {
            return CGSize(width: CGFloat(height), height: CGFloat(width))
        }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }
}

#if canImport(AppKit)
struct ScrollWheelZoomMonitor: NSViewRepresentable {
    let onScroll: (CompareWheelZoomEvent) -> Void

    func makeNSView(context: Context) -> ScrollWheelZoomView {
        let view = ScrollWheelZoomView(frame: .zero)
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelZoomView, context: Context) {
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: ScrollWheelZoomView, coordinator: ()) {
        nsView.stopMonitoring()
        nsView.onScroll = nil
    }
}

final class ScrollWheelZoomView: NSView {
    var onScroll: ((CompareWheelZoomEvent) -> Void)?
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            installMonitorIfNeeded()
        }
    }

    private func installMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.shouldHandleScroll(in: event.window) else { return event }
            let locationInView = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(locationInView) else { return event }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 10
            self.onScroll?(
                CompareWheelZoomEvent(
                    deltaY: delta,
                    location: CGPoint(
                        x: locationInView.x,
                        y: self.bounds.height - locationInView.y
                    )
                )
            )
            return event
        }
    }

    func shouldHandleScroll(in eventWindow: NSWindow?) -> Bool {
        guard let window, eventWindow === window else { return false }
        return window.attachedSheet == nil && !isHiddenOrHasHiddenAncestor
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
#endif
