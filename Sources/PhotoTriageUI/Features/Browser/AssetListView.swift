import PhotoTriageCore
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

public struct AssetListView: View {
    @EnvironmentObject private var state: AppState
    // Only the tiny scroll indicator observes these changes. Updating @State
    // offsets here used to rebuild the entire list on every scroll frame.
    @State private var scrollMetrics = AssetListScrollMetrics()
    @State private var assetFrames: [UUID: CGRect] = [:]
    @State private var dragStartPoint: CGPoint?
    @State private var selectionDragRect: CGRect?
    @State private var selectionDragInitialIDs: Set<UUID> = []

    // Let the grid distribute the available width instead of capping every card at
    // 300pt.  This keeps thumbnails useful when the main window is widened and
    // naturally increases the number of columns when it is narrowed.
    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 18)]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    scrollOffsetTracker

                    assetContent
                        .padding(20)
                        .background(contentHeightTracker)
                }
                .onChange(of: state.selectedAssetID) { _, assetID in
                    scrollToSelectedAsset(assetID, with: scrollProxy)
                }
                .onChange(of: state.currentCompareGroupScrollTargetAssetID) { _, assetID in
                    scrollToSelectedAsset(assetID, with: scrollProxy)
                }
                .onChange(of: state.currentBasenameCompareGroupNumber) { _, _ in
                    scrollToSelectedAsset(state.currentCompareGroupScrollTargetAssetID, with: scrollProxy)
                }
                .onChange(of: state.mode) { _, mode in
                    guard mode == .grid else { return }
                    scrollToSelectedAsset(state.currentCompareGroupScrollTargetAssetID, with: scrollProxy)
                }
            }
            .coordinateSpace(name: "asset-list-scroll")
            .background(viewportHeightTracker)
            .simultaneousGesture(selectionDragGesture)
            .overlay {
                if let selectionDragRect {
                    Rectangle()
                        .fill(AppTheme.accentLime.opacity(0.16))
                        .overlay {
                            Rectangle()
                                .stroke(AppTheme.accentLime.opacity(0.82), lineWidth: 1)
                        }
                        .frame(width: selectionDragRect.width, height: selectionDragRect.height)
                        .position(x: selectionDragRect.midX, y: selectionDragRect.midY)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .trailing) {
                AssetListScrollIndicator(metrics: scrollMetrics)
                .padding(.trailing, 10)
                .padding(.vertical, 16)
            }
            .overlay {
                if state.isLoading && state.visibleThumbnailAssetCount == 0 {
                    AssetListLoadingOverlay()
                }
            }
        }
        .overlay {
            if state.visibleThumbnailAssetCount == 0, !state.isLoading {
                AssetListEmptyState()
            }
        }
        .onPreferenceChange(AssetListViewportHeightPreferenceKey.self) { scrollMetrics.viewportHeight = max($0, 1) }
        .onPreferenceChange(AssetListContentHeightPreferenceKey.self) { scrollMetrics.contentHeight = max($0, 1) }
        .onPreferenceChange(AssetListScrollOffsetPreferenceKey.self) { scrollMetrics.scrollOffset = max($0, 0) }
        .onPreferenceChange(AssetFramePreferenceKey.self) { assetFrames = $0 }
    }

    @ViewBuilder
    private var assetContent: some View {
        if state.compareFolderOrder.count > 1 {
            AssetListAlignedRowsSection(
                columnTitles: state.compareFolderOrder,
                rows: state.visibleCompareRows,
                selectedAssetIDs: state.selectedAssetIDs,
                isCollectingFrames: selectionDragRect != nil,
                refreshToken: { state.imageRefreshToken(for: $0.id) },
                fileURL: { state.fileURL(for: $0) },
                isViewed: { state.isAssetInViewedCompareGroup($0.id) },
                onToggleSelection: { state.toggleSelection(assetID: $0) },
                onOpenAsset: { assetID in
                    state.enterSingleImageViewer(assetID: assetID)
                },
                onApplyRating: { rating, assetID in
                    state.applyRating(rating, to: [assetID])
                },
                onApplyPriorityTag: { priorityTag, assetID in
                    state.applyPriorityTag(priorityTag, to: [assetID])
                },
                onClearPriorityTag: { assetID in
                    state.clearPriorityTags(from: [assetID])
                },
                onClearAllTags: { assetID in
                    state.clearAllTriageTags(from: [assetID])
                }
            )
        } else {
            AssetListGridSection(
                columns: columns,
                assets: state.filteredAssets,
                selectedAssetIDs: state.selectedAssetIDs,
                isCollectingFrames: selectionDragRect != nil,
                refreshToken: { state.imageRefreshToken(for: $0.id) },
                fileURL: { state.fileURL(for: $0) },
                isViewed: { state.isAssetInViewedCompareGroup($0.id) },
                onToggleSelection: { state.toggleSelection(assetID: $0) },
                onOpenAsset: { assetID in
                    state.enterSingleImageViewer(assetID: assetID)
                },
                onApplyRating: { rating, assetID in
                    state.applyRating(rating, to: [assetID])
                },
                onApplyPriorityTag: { priorityTag, assetID in
                    state.applyPriorityTag(priorityTag, to: [assetID])
                },
                onClearPriorityTag: { assetID in
                    state.clearPriorityTags(from: [assetID])
                },
                onClearAllTags: { assetID in
                    state.clearAllTriageTags(from: [assetID])
                }
            )
        }
    }

    private var scrollOffsetTracker: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: AssetListScrollOffsetPreferenceKey.self,
                    value: -proxy.frame(in: .named("asset-list-scroll")).minY
                )
        }
        .frame(height: 0)
    }

    private var contentHeightTracker: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: AssetListContentHeightPreferenceKey.self, value: proxy.size.height)
        }
    }

    private var viewportHeightTracker: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: AssetListViewportHeightPreferenceKey.self, value: proxy.size.height)
        }
    }

    private var selectionDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("asset-list-scroll"))
            .onChanged { value in
                if dragStartPoint == nil {
                    dragStartPoint = value.startLocation
                    selectionDragInitialIDs = state.selectedAssetIDs
                    assetFrames = [:]
                }

                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                selectionDragRect = rect

                let intersectedIDs = Set(assetFrames.compactMap { assetID, frame in
                    frame.intersects(rect) ? assetID : nil
                })

                if isCommandPressed {
                    state.setSelection(assetIDs: selectionDragInitialIDs.union(intersectedIDs))
                } else {
                    state.setSelection(assetIDs: intersectedIDs)
                }
            }
            .onEnded { _ in
                dragStartPoint = nil
                selectionDragRect = nil
                selectionDragInitialIDs = []
                assetFrames = [:]
            }
    }

    private var isCommandPressed: Bool {
        #if canImport(AppKit)
        NSApp.currentEvent?.modifierFlags.contains(.command) == true
        #else
        false
        #endif
    }

    private func scrollToSelectedAsset(_ assetID: UUID?, with proxy: ScrollViewProxy) {
        guard let assetID else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(assetID, anchor: .center)
            }
        }
    }
}

private struct AssetListGridSection: View {
    let columns: [GridItem]
    let assets: [AssetRecord]
    let selectedAssetIDs: Set<UUID>
    let isCollectingFrames: Bool
    let refreshToken: (AssetRecord) -> UUID
    let fileURL: (AssetRecord) -> URL?
    let isViewed: (AssetRecord) -> Bool
    let onToggleSelection: (UUID) -> Void
    let onOpenAsset: (UUID) -> Void
    let onApplyRating: (RatingState, UUID) -> Void
    let onApplyPriorityTag: (PriorityTag, UUID) -> Void
    let onClearPriorityTag: (UUID) -> Void
    let onClearAllTags: (UUID) -> Void

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(assets) { asset in
                AssetGridSelectionButton(
                    asset: asset,
                    fileURL: fileURL(asset),
                    refreshToken: refreshToken(asset),
                    isSelected: selectedAssetIDs.contains(asset.id),
                    isViewed: isViewed(asset),
                    onToggleSelection: { onToggleSelection(asset.id) },
                    onOpenAsset: { onOpenAsset(asset.id) },
                    onApplyRating: { rating in onApplyRating(rating, asset.id) },
                    onApplyPriorityTag: { priorityTag in onApplyPriorityTag(priorityTag, asset.id) },
                    onClearPriorityTag: { onClearPriorityTag(asset.id) },
                    onClearAllTags: { onClearAllTags(asset.id) }
                )
                .id(asset.id)
                .assetFramePreference(assetID: asset.id, isEnabled: isCollectingFrames)
            }
        }
    }
}

private struct AssetListAlignedRowsSection: View {
    private let columnSpacing: CGFloat = 12
    private let rowSpacing: CGFloat = 14

    let columnTitles: [String]
    let rows: [[AssetRecord?]]
    let selectedAssetIDs: Set<UUID>
    let isCollectingFrames: Bool
    let refreshToken: (AssetRecord) -> UUID
    let fileURL: (AssetRecord) -> URL?
    let isViewed: (AssetRecord) -> Bool
    let onToggleSelection: (UUID) -> Void
    let onOpenAsset: (UUID) -> Void
    let onApplyRating: (RatingState, UUID) -> Void
    let onApplyPriorityTag: (PriorityTag, UUID) -> Void
    let onClearPriorityTag: (UUID) -> Void
    let onClearAllTags: (UUID) -> Void

    var body: some View {
        // Compute once per section update, not once for every realized row.
        let columnCount = max(columnTitles.count, rows.lazy.map(\.count).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: columnSpacing) {
                ForEach(0..<columnCount, id: \.self) { columnIndex in
                    CompareColumnHeader(title: columnTitle(at: columnIndex))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LazyVStack(spacing: rowSpacing) {
                ForEach(rows.indices, id: \.self) { rowIndex in
                    let row = rows[rowIndex]
                    HStack(alignment: .top, spacing: columnSpacing) {
                        ForEach(0..<columnCount, id: \.self) { columnIndex in
                            Group {
                                if row.indices.contains(columnIndex), let asset = row[columnIndex] {
                                    AssetCompareSelectionButton(
                                        asset: asset,
                                        fileURL: fileURL(asset),
                                        refreshToken: refreshToken(asset),
                                        isSelected: selectedAssetIDs.contains(asset.id),
                                        isViewed: isViewed(asset),
                                        onToggleSelection: { onToggleSelection(asset.id) },
                                        onOpenAsset: { onOpenAsset(asset.id) },
                                        onApplyRating: { rating in onApplyRating(rating, asset.id) },
                                        onApplyPriorityTag: { priorityTag in onApplyPriorityTag(priorityTag, asset.id) },
                                        onClearPriorityTag: { onClearPriorityTag(asset.id) },
                                        onClearAllTags: { onClearAllTags(asset.id) }
                                    )
                                    .assetFramePreference(assetID: asset.id, isEnabled: isCollectingFrames)
                                } else {
                                    AssetCompareEmptySlot()
                                    }
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .id(rowScrollTargetID(for: row))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func columnTitle(at index: Int) -> String {
        guard columnTitles.indices.contains(index) else { return "目录 \(index + 1)" }
        let title = columnTitles[index].split(separator: "/").last.map(String.init) ?? columnTitles[index]
        return title.isEmpty ? columnTitles[index] : title
    }

    private func rowScrollTargetID(for row: [AssetRecord?]) -> UUID? {
        row.compactMap(\.self).first?.id
    }
}

private struct CompareColumnHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .background(AppTheme.rowFill.opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.borderSoft.opacity(0.9), lineWidth: 1)
        }
    }
}

private struct AssetCompareSelectionButton: View {
    let asset: AssetRecord
    let fileURL: URL?
    let refreshToken: UUID
    let isSelected: Bool
    let isViewed: Bool
    let onToggleSelection: () -> Void
    let onOpenAsset: () -> Void
    let onApplyRating: (RatingState) -> Void
    let onApplyPriorityTag: (PriorityTag) -> Void
    let onClearPriorityTag: () -> Void
    let onClearAllTags: () -> Void

    var body: some View {
        Button(action: onToggleSelection) {
            AssetCompareThumbnailCard(
                asset: asset,
                fileURL: fileURL,
                refreshToken: refreshToken,
                isSelected: isSelected,
                isViewed: isViewed
            )
            .equatable()
        }
        .buttonStyle(SelectionCardButtonStyle(isSelected: isSelected))
        .simultaneousGesture(TapGesture(count: 2).onEnded(onOpenAsset))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(asset.filename)
        .accessibilityValue(assetAccessibilityValue(asset, isSelected: isSelected, isViewed: isViewed))
        .accessibilityHint("单击选择，双击查看")
        .contextMenu {
            Button("保留（A）") { onApplyRating(.keep) }
            Button("恢复（S）") { onApplyRating(.pending) }
            Button("淘汰（D）") { onApplyRating(.reject) }
            Divider()
            PriorityTagContextMenu(onApply: onApplyPriorityTag)
            Button("清除 P 标签") { onClearPriorityTag() }
            Button("清除此图标签（X）") { onClearAllTags() }
        }
    }
}

struct AssetCompareThumbnailCard: View, Equatable {
    let asset: AssetRecord
    let fileURL: URL?
    let refreshToken: UUID
    let isSelected: Bool
    let isViewed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThumbnailPlaceholder(asset: asset, fileURL: fileURL, maxPixelSize: 420, refreshToken: refreshToken)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.6, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topLeading) {
                    RatingBadge(rating: asset.ratingState)
                        .padding(8)
                }
                .overlay(alignment: .bottomLeading) {
                    if let priorityTag = asset.priorityTag {
                        TagPill(tag: priorityTag.appTag)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isViewed {
                        AppStatusPill("已看", status: .focused, systemImage: "eye")
                            .padding(8)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    AppCapsuleLabel(asset.format.badge)
                        .padding(8)
                }

            Text(asset.filename)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(asset.relativePath)
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 6) {
                AppStatusPill(asset.dimensionDescription, status: asset.hasKnownDimensions ? .neutral : .loading)
                if isSelected {
                    AppStatusPill("已选", status: .selected)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct AssetCompareEmptySlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(AppTheme.rowFill.opacity(0.35))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title3.weight(.semibold))
                    Text("缺少同名文件")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(AppTheme.textMuted)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.borderSoft, style: StrokeStyle(lineWidth: 1, dash: [6, 7]))
            }
            .aspectRatio(1.25, contentMode: .fit)
            .frame(maxWidth: .infinity)
    }
}

private struct AssetFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private extension View {
    @ViewBuilder
    func assetFramePreference(assetID: UUID, isEnabled: Bool) -> some View {
        if isEnabled {
            background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: AssetFramePreferenceKey.self,
                        value: [assetID: proxy.frame(in: .named("asset-list-scroll"))]
                    )
                }
            }
        } else {
            self
        }
    }
}

private struct AssetGridSelectionButton: View {
    let asset: AssetRecord
    let fileURL: URL?
    let refreshToken: UUID
    let isSelected: Bool
    let isViewed: Bool
    let onToggleSelection: () -> Void
    let onOpenAsset: () -> Void
    let onApplyRating: (RatingState) -> Void
    let onApplyPriorityTag: (PriorityTag) -> Void
    let onClearPriorityTag: () -> Void
    let onClearAllTags: () -> Void

    var body: some View {
        Button(action: onToggleSelection) {
            AssetGridCard(
                asset: asset,
                fileURL: fileURL,
                refreshToken: refreshToken,
                isSelected: isSelected,
                isViewed: isViewed
            )
            .equatable()
        }
        .buttonStyle(SelectionCardButtonStyle(isSelected: isSelected))
        .simultaneousGesture(TapGesture(count: 2).onEnded(onOpenAsset))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(asset.filename)
        .accessibilityValue(assetAccessibilityValue(asset, isSelected: isSelected, isViewed: isViewed))
        .accessibilityHint("单击选择，双击查看")
        .contextMenu {
            Button("保留（A）") { onApplyRating(.keep) }
            Button("恢复（S）") { onApplyRating(.pending) }
            Button("淘汰（D）") { onApplyRating(.reject) }
            Divider()
            PriorityTagContextMenu(onApply: onApplyPriorityTag)
            Button("清除 P 标签") { onClearPriorityTag() }
            Button("清除此图标签（X）") { onClearAllTags() }
        }
    }
}

struct AssetGridCard: View, Equatable {
    let asset: AssetRecord
    let fileURL: URL?
    let refreshToken: UUID
    let isSelected: Bool
    let isViewed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThumbnailPlaceholder(asset: asset, fileURL: fileURL, maxPixelSize: 520, refreshToken: refreshToken)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.6, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topLeading) {
                    RatingBadge(rating: asset.ratingState)
                        .padding(10)
                }
                .overlay(alignment: .bottomLeading) {
                    if let priorityTag = asset.priorityTag {
                        TagPill(tag: priorityTag.appTag)
                            .padding(10)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    AppCapsuleLabel(asset.format.badge)
                        .padding(10)
                }
                .overlay(alignment: .topTrailing) {
                    if isViewed {
                        AppStatusPill("已看过", status: .focused, systemImage: "eye")
                            .padding(10)
                    }
                }

            VStack(alignment: .leading, spacing: 8) {
                Text(asset.filename)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(asset.relativePath)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    AppStatusPill(asset.dimensionDescription, status: asset.hasKnownDimensions ? .neutral : .loading)
                    AppStatusPill(asset.isRaw ? "RAW" : "图像", status: asset.isRaw ? .loading : .neutral)
                    if isSelected {
                        AppStatusPill("已选", status: .selected)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct AssetListEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.accentPeach)
            Text("没有匹配素材")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            Text("换个搜索词、切回全部范围，或从左侧导入目录。")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(22)
        .appSurface(.card)
    }
}

private struct AssetListLoadingOverlay: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(AppTheme.accentLime)
                VStack(alignment: .leading, spacing: 4) {
                    Text("正在刷新素材")
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("列表会先出现，缩略图随后补齐。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .appSurface(.card)
    }
}

@MainActor
final class AssetListScrollMetrics: ObservableObject {
    @Published var viewportHeight: CGFloat = 1
    @Published var contentHeight: CGFloat = 1
    @Published var scrollOffset: CGFloat = 0

    var progress: CGFloat {
        let totalScrollableHeight = contentHeight - viewportHeight
        guard totalScrollableHeight > 1 else { return 0 }
        return min(max(scrollOffset / totalScrollableHeight, 0), 1)
    }
}

private struct AssetListScrollIndicator: View {
    @ObservedObject var metrics: AssetListScrollMetrics

    var body: some View {
        VerticalScrollProgressBar(
            progress: metrics.progress,
            viewportHeight: metrics.viewportHeight,
            contentHeight: metrics.contentHeight
        )
    }
}

private struct VerticalScrollProgressBar: View {
    let progress: CGFloat
    let viewportHeight: CGFloat
    let contentHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            if contentHeight > viewportHeight + 1 {
                let trackHeight = max(proxy.size.height, 1)
                let thumbHeight = min(
                    trackHeight,
                    max(48, trackHeight * (viewportHeight / max(contentHeight, viewportHeight)))
                )
                let travel = max(trackHeight - thumbHeight, 0)

                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accentLime.opacity(0.95), AppTheme.accentLime.opacity(0.45)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: thumbHeight)
                        .offset(y: travel * progress)
                }
                .frame(width: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: 16)
    }
}

private struct AssetListViewportHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct AssetListContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct AssetListScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private func assetAccessibilityValue(_ asset: AssetRecord, isSelected: Bool, isViewed: Bool) -> String {
    var parts = [
        asset.relativePath,
        ratingAccessibilityLabel(asset.ratingState),
        asset.dimensionDescription,
        asset.format.badge,
    ]

    if let priorityTag = asset.priorityTag {
        parts.append(priorityTag.displayName)
    }
    if isSelected {
        parts.append("已选中")
    }
    if isViewed {
        parts.append("已查看")
    }

    return parts.joined(separator: "，")
}

private func ratingAccessibilityLabel(_ rating: RatingState) -> String {
    switch rating {
    case .keep:
        return "保留"
    case .reject:
        return "淘汰"
    case .pending:
        return "未处理"
    }
}
