import Foundation
import PhotoTriageCore
import SwiftUI

public struct InspectorPanelView: View {
    @EnvironmentObject private var state: AppState

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let asset = state.selectedAsset {
                    InspectorPreviewCard(
                        asset: asset,
                        fileURL: state.fileURL(for: asset),
                        refreshToken: state.imageRefreshToken(for: asset.id)
                    )
                    InspectorInfoCard(
                        asset: asset,
                        libraryName: libraryName(for: asset.libraryID)
                    )
                    InspectorActionCard(
                        hasFocusedSelection: !state.focusedAssetIDs.isEmpty,
                        focusedAssetIDs: state.focusedAssetIDs,
                        priorityTag: asset.priorityTag,
                        onKeep: { state.applyRatingToFocusedSelection(.keep) },
                        onReject: { state.applyRatingToFocusedSelection(.reject) },
                        onReset: { state.applyRatingToFocusedSelection(.pending) },
                        onP0: { state.applyPriorityTagToFocusedSelection(.p0) },
                        onP1: { state.applyPriorityTagToFocusedSelection(.p1) },
                        onP2: { state.applyPriorityTagToFocusedSelection(.p2) },
                        onClearPriorityTag: { state.clearPriorityTagsFromFocusedSelection() },
                        onClearAllTags: { state.clearAllTriageTagsFromFocusedSelection() },
                        onRevealInFinder: { state.revealSelectedAssetInFinder() },
                        onQuickLook: { state.quickLookSelectedAsset() },
                        onDelete: { state.deleteFocusedAssets() }
                    )
                } else {
                    InspectorEmptyCard()
                }
            }
            .padding(16)
        }
        .background(AppWorkspaceBackdrop())
    }

    private func libraryName(for libraryID: UUID) -> String {
        state.libraries.first(where: { $0.id == libraryID })?.displayName ?? "未知目录"
    }
}

private struct InspectorPreviewCard: View {
    let asset: AssetRecord
    let fileURL: URL?
    let refreshToken: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ThumbnailPlaceholder(asset: asset, fileURL: fileURL, contentMode: .fit, maxPixelSize: 720, refreshToken: refreshToken)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topLeading) {
                    RatingBadge(rating: asset.ratingState)
                        .padding(12)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(asset.filename)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(asset.relativePath)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(3)

                if !asset.appTags.isEmpty {
                    FlowTags(tags: asset.appTags)
                }
            }
        }
        .appSurface(.panel)
    }
}

private struct InspectorInfoCard: View {
    @EnvironmentObject private var state: AppState
    let asset: AssetRecord
    let libraryName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionTitle("信息")
            InspectorInfoLine(label: "格式", value: asset.format.badge)
            InspectorInfoLine(label: "尺寸", value: asset.dimensionDescription)
            InspectorInfoLine(label: "大小", value: ByteCountFormatter.string(fromByteCount: Int64(asset.fileSizeBytes), countStyle: .file))
            InspectorInfoLine(label: "状态", value: asset.ratingState.label)
            InspectorInfoLine(label: "P 标签", value: asset.priorityTag.map(state.priorityTagDisplayName) ?? "无")
            InspectorInfoLine(label: "加入", value: addedDateText)
            InspectorInfoLine(label: "目录", value: libraryName)
        }
        .appSurface(.panel)
    }

    private var addedDateText: String {
        guard let date = asset.addedToDirectoryDate else { return "未知" }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct InspectorActionCard: View {
    @EnvironmentObject private var state: AppState
    let hasFocusedSelection: Bool
    let focusedAssetIDs: [UUID]
    let priorityTag: PriorityTag?
    let onKeep: () -> Void
    let onReject: () -> Void
    let onReset: () -> Void
    let onP0: () -> Void
    let onP1: () -> Void
    let onP2: () -> Void
    let onClearPriorityTag: () -> Void
    let onClearAllTags: () -> Void
    let onRevealInFinder: () -> Void
    let onQuickLook: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionTitle("操作", subtitle: "当前选中素材")

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    AppStatusPill("主操作", status: .selected)
                }
                HStack(spacing: 10) {
                    Button {
                        onKeep()
                    } label: {
                        Label("保留", systemImage: "heart.fill")
                    }
                    .appButtonStyle(.primary)
                    .disabled(!hasFocusedSelection)
                    .help(hasFocusedSelection ? "标记为保留" : "当前没有可操作素材")

                    Button {
                        onReject()
                    } label: {
                        Label("淘汰", systemImage: "xmark")
                    }
                    .appButtonStyle(.secondary)
                    .disabled(!hasFocusedSelection)
                    .help(hasFocusedSelection ? "标记为淘汰" : "当前没有可操作素材")

                    Button {
                        onReset()
                    } label: {
                        Label("恢复", systemImage: "arrow.uturn.backward")
                    }
                    .appButtonStyle(.toolbar)
                    .disabled(!hasFocusedSelection)
                    .help(hasFocusedSelection ? "恢复为未处理" : "当前没有可操作素材")
                }
            }

            Divider()
                .overlay(AppTheme.borderSoft)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    AppStatusPill("P 标签", status: priorityTag == nil ? .neutral : .selected)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(state.priorityTags) { tag in
                        priorityButton(tag) { state.applyPriorityTagToFocusedSelection(tag) }
                    }
                    Button {
                        onClearPriorityTag()
                    } label: {
                        Label("清除", systemImage: "tag.slash")
                    }
                    .appButtonStyle(.toolbar)
                    .disabled(priorityTag == nil || !hasFocusedSelection)
                    .help(priorityTag == nil ? "当前没有 P 标签" : "清除 P 标签")
                }

                Button {
                    onClearAllTags()
                } label: {
                    Label("清除选中标签", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .appButtonStyle(.toolbar)
                .disabled(!hasFocusedSelection)
                .help(hasFocusedSelection ? "清除当前选中素材的筛选标签" : "当前没有可操作素材")
            }

            Divider()
                .overlay(AppTheme.borderSoft)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    AppStatusPill("辅助", status: .neutral)
                }
                Button {
                    onRevealInFinder()
                } label: {
                    Label("Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .appButtonStyle(.secondary)

                Button {
                    onQuickLook()
                } label: {
                    Label("快速预览", systemImage: "eye")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .appButtonStyle(.secondary)
            }

            Divider()
                .overlay(AppTheme.borderSoft)

            VStack(alignment: .leading, spacing: 10) {
                AppStatusPill("危险操作", status: .danger)
                Button {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .appButtonStyle(.destructive)
                .disabled(!hasFocusedSelection)
                .help(hasFocusedSelection ? "删除当前选中素材" : "当前没有可操作素材")
            }
        }
        .appSurface(.panel)
    }

    private func priorityButton(_ tag: PriorityTag, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(state.priorityTagDisplayName(tag)).lineLimit(2)
                .font(.callout.weight(.semibold))
                .frame(minWidth: 38)
        }
        .buttonStyle(PriorityTagButtonStyle(tag: tag, isSelected: priorityTag == tag))
        .disabled(!hasFocusedSelection)
        .help(hasFocusedSelection ? "设置 \(state.priorityTagDisplayName(tag))" : "当前没有可操作素材")
    }
}

private struct PriorityTagButtonStyle: ButtonStyle {
    let tag: PriorityTag
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let tint = TagPill.tintColor(for: tag)
        configuration.label
            .foregroundStyle(isSelected ? AppTheme.textOnAccent : tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? tint.opacity(configuration.isPressed ? 0.78 : 0.95) : tint.opacity(configuration.isPressed ? 0.20 : 0.13),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(isSelected ? 0.20 : 0.46), lineWidth: 1)
            }
    }
}

private struct FlowTags: View {
    let tags: [AppTag]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags.prefix(5)) { tag in
                TagPill(tag: tag)
            }
        }
    }
}

private struct InspectorEmptyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 30))
                .foregroundStyle(AppTheme.accentLime)
            Text("选一张图")
                .font(.headline)
                .foregroundStyle(AppTheme.textOnDark)
            Text("点击中间网格素材后，这里会显示预览、文件信息和操作入口。")
                .font(.caption)
                .foregroundStyle(AppTheme.textOnDarkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .appSurface(.hero)
        .colorScheme(.dark)
    }
}

private struct InspectorInfoLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(AppTheme.textMuted)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .font(.caption)
    }
}

private extension RatingState {
    var label: String {
        switch self {
        case .keep:
            return "保留"
        case .reject:
            return "淘汰"
        case .pending:
            return "未处理"
        }
    }
}
