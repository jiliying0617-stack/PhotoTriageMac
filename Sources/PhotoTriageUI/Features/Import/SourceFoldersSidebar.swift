import PhotoTriageCore
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

public struct SourceFoldersSidebar: View {
    @EnvironmentObject private var state: AppState
    @State private var expandedLibraryIDs: Set<UUID> = []
    @State private var isTargetedForFolderDrop = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ImportSourcesCard(
                    isTargetedForFolderDrop: isTargetedForFolderDrop,
                    onChooseFolders: chooseFolders,
                    onUseSampleData: {
                        WorkspaceFolderImportController.useSampleData(with: state)
                    }
                )
                WorkspaceSummaryCard(
                    libraries: state.libraries,
                    totalCount: state.totalCount,
                    activeFilterDescription: state.activeFilterDescription,
                    sortMode: state.assetSortMode,
                    onSelectSortMode: state.selectAssetSortMode
                )
                LibrariesPanelCard(
                    libraries: state.libraries,
                    selectedLibraryID: state.selectedLibraryID,
                    selectedFolderPath: state.selectedFolderPath,
                    selectedFolderPaths: state.selectedFolderPaths,
                    bindingForExpansion: bindingForLibraryExpansion,
                    libraryAssetCount: state.libraryAssetCount,
                    folderTree: state.folderTree(for:),
                    onSelectLibrary: state.selectLibrary
                )
                MissingImagesCard(
                    compareFolderOrder: state.compareFolderOrder,
                    missingGroups: state.missingCompareGroups,
                    missingAssetCount: state.missingCompareAssetCount,
                    isMatchingImageContent: state.isMatchingImageContent
                )
            }
            .padding(16)
        }
        .background(AppWorkspaceBackdrop())
        .onAppear {
            expandedLibraryIDs.formUnion(state.libraries.map(\.id))
        }
        .onChange(of: state.libraries.map(\.id)) { _, newIDs in
            expandedLibraryIDs.formUnion(newIDs)
        }
        .dropDestination(for: URL.self) { urls, location in
            WorkspaceFolderImportController.handleFolderDrop(urls, with: state)
        } isTargeted: { isTargeted in
            isTargetedForFolderDrop = isTargeted
        }
    }

    private func bindingForLibraryExpansion(_ libraryID: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedLibraryIDs.contains(libraryID) },
            set: { isExpanded in
                if isExpanded {
                    expandedLibraryIDs.insert(libraryID)
                } else {
                    expandedLibraryIDs.remove(libraryID)
                }
            }
        )
    }

    private func chooseFolders() {
        WorkspaceFolderImportController.chooseFolders(using: state)
    }
}

private struct ImportSourcesCard: View {
    let isTargetedForFolderDrop: Bool
    let onChooseFolders: () -> Void
    let onUseSampleData: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                AppSectionTitle("导入素材", subtitle: isTargetedForFolderDrop ? "松手导入这批目录" : "选择或拖入待筛目录")
                Spacer()
                Image(systemName: "square.and.arrow.down.on.square")
                    .foregroundStyle(AppTheme.accentLime)
            }

            VStack(spacing: 10) {
                Button {
                    onChooseFolders()
                } label: {
                    Label("选择文件夹", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .appButtonStyle(.primary)

                Button {
                    onUseSampleData()
                } label: {
                    Label("示例数据", systemImage: "sparkles.rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .appButtonStyle(.secondary)
            }
        }
        .appSurface(.hero)
        .colorScheme(.dark)
        .overlay {
            if isTargetedForFolderDrop {
                RoundedRectangle(cornerRadius: AppChromeTokens.panelCornerRadius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
    }
}

private struct WorkspaceSummaryCard: View {
    let libraries: [LibraryFolder]
    let totalCount: Int
    let activeFilterDescription: String
    let sortMode: AssetSortMode
    let onSelectSortMode: (AssetSortMode) -> Void

    var body: some View {
        if libraries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                AppSectionTitle("当前范围")
                Text("还没有目录")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .appSurface(.panel)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                AppSectionTitle("当前范围", subtitle: activeFilterDescription)

                HStack(spacing: 10) {
                    SidebarMetric(title: "命中", value: totalCount, tint: AppTheme.accentLime)
                }

                Divider()
                    .overlay(AppTheme.borderSoft)

                SidebarSortModeControl(
                    selectedSortMode: sortMode,
                    onSelect: onSelectSortMode
                )
            }
            .appSurface(.panel)
        }
    }
}

private struct SidebarSortModeControl: View {
    let selectedSortMode: AssetSortMode
    let onSelect: (AssetSortMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("排序")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.textMuted)
                .textCase(.uppercase)

            HStack(spacing: 6) {
                sortButton(.addedDate)
                sortButton(.filename)
            }
        }
    }

    private func sortButton(_ sortMode: AssetSortMode) -> some View {
        Button {
            onSelect(sortMode)
        } label: {
            Text(sortMode == .addedDate ? "添加时间" : "文件名")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selectedSortMode == sortMode ? AppTheme.textOnAccent : AppTheme.textSecondary)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selectedSortMode == sortMode ? AppTheme.accentLime : AppTheme.rowFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(selectedSortMode == sortMode ? AppTheme.accentLime.opacity(0.7) : AppTheme.borderSoft, lineWidth: 1)
        }
    }
}

private struct LibrariesPanelCard: View {
    let libraries: [LibraryFolder]
    let selectedLibraryID: UUID?
    let selectedFolderPath: String?
    let selectedFolderPaths: Set<String>
    let bindingForExpansion: (UUID) -> Binding<Bool>
    let libraryAssetCount: (UUID) -> Int
    let folderTree: (UUID) -> [FolderTreeNode]
    let onSelectLibrary: (UUID?) -> Void

    var body: some View {
        if !libraries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    AppSectionTitle("素材目录", subtitle: "库根与子目录筛选")
                    Spacer()
                    Button {
                        onSelectLibrary(nil)
                    } label: {
                        Label("全部", systemImage: "tray.full")
                    }
                    .appButtonStyle(selectedLibraryID == nil ? .primary : .toolbar)
                }

                ForEach(libraries) { library in
                    DisclosureGroup(isExpanded: bindingForExpansion(library.id)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                onSelectLibrary(library.id)
                            } label: {
                                SidebarSelectionRow(
                                    title: "全部",
                                    subtitle: library.path,
                                    systemImage: "folder",
                                    trailingText: "\(libraryAssetCount(library.id))",
                                    isSelected: isLibraryRootSelected(library.id),
                                    indentation: 14
                                )
                            }
                            .buttonStyle(SidebarRowButtonStyle(isSelected: isLibraryRootSelected(library.id)))

                            ForEach(folderTree(library.id)) { node in
                                FolderTreeRow(node: node, level: 1)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "externaldrive")
                                .foregroundStyle(isLibrarySelected(library.id) ? AppTheme.accentLime : AppTheme.textSecondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(library.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text(library.path)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            AppStatusPill("\(libraryAssetCount(library.id))", status: isLibrarySelected(library.id) ? .selected : .neutral)
                        }
                        .padding(.vertical, 4)
                    }
                    .tint(AppTheme.textPrimary)
                }
            }
            .appSurface(.panel)
        }
    }

    private func isLibraryRootSelected(_ libraryID: UUID) -> Bool {
        selectedLibraryID == libraryID && selectedFolderPaths.isEmpty
    }

    private func isLibrarySelected(_ libraryID: UUID) -> Bool {
        selectedLibraryID == libraryID
    }
}

private struct MissingImagesCard: View {
    let compareFolderOrder: [String]
    let missingGroups: [MissingCompareGroup]
    let missingAssetCount: Int
    let isMatchingImageContent: Bool
    @State private var isExpanded = false

    var body: some View {
        if compareFolderOrder.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup(isExpanded: $isExpanded) {
                    if isMatchingImageContent {
                        Label("正在用缩略图进行二次配对…", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.vertical, 4)
                    } else if missingGroups.isEmpty {
                        Text("当前目录已完整配对。")
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(missingGroups) { group in
                                MissingImageRow(group: group)
                            }
                        }
                        .padding(.top, 8)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundStyle(
                                isMatchingImageContent
                                    ? AppTheme.accentLime
                                    : (missingGroups.isEmpty ? AppTheme.textSecondary : AppTheme.accentPeach)
                            )
                        AppSectionTitle(
                            "丢失图片",
                            subtitle: isMatchingImageContent ? "正在进行缩略图内容检测" : "文件名与图片内容均未配对"
                        )
                        Spacer()
                        AppStatusPill(
                            isMatchingImageContent ? "检测中" : "\(missingAssetCount)",
                            status: isMatchingImageContent ? .focused : (missingGroups.isEmpty ? .neutral : .loading),
                            systemImage: isMatchingImageContent ? "sparkles" : "exclamationmark.triangle"
                        )
                    }
                }
                .tint(AppTheme.textPrimary)
            }
            .appSurface(.panel)
        }
    }
}

private struct MissingImageRow: View {
    @EnvironmentObject private var state: AppState
    let group: MissingCompareGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(AppTheme.accentPeach)
                Text(group.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                AppStatusPill("缺 \(group.missingFolderPaths.count)", status: .loading)
            }

            Text("缺少：\(group.missingFolderPaths.joined(separator: "、"))")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)

            if !group.presentAssets.isEmpty {
                Text("已有：\(group.presentAssets.map(\.relativePath).joined(separator: "、"))")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textMuted)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(AppTheme.rowFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu {
            ForEach(group.presentAssets) { asset in
                Button {
                    state.revealAssetInFinder(asset)
                } label: {
                    Label("在 Finder 中显示 \(asset.relativePath)", systemImage: "folder")
                }
            }
        }
    }
}

private struct FolderTreeRow: View {
    @EnvironmentObject private var state: AppState
    let node: FolderTreeNode
    let level: Int
    @State private var isExpanded = true

    var body: some View {
        if node.children.isEmpty {
            Button {
                selectNode()
            } label: {
                SidebarSelectionRow(
                    title: node.name,
                    subtitle: node.relativePath,
                    systemImage: "folder",
                    trailingText: "\(node.assetCount)",
                    isSelected: isSelected,
                    indentation: CGFloat(level) * 14
                )
            }
            .buttonStyle(SidebarRowButtonStyle(isSelected: isSelected))
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(node.children) { child in
                    FolderTreeRow(node: child, level: level + 1)
                }
            } label: {
                Button {
                    selectNode()
                } label: {
                    SidebarSelectionRow(
                        title: node.name,
                        subtitle: node.relativePath,
                        systemImage: "folder",
                        trailingText: "\(node.assetCount)",
                        isSelected: isSelected,
                        indentation: CGFloat(level) * 14
                    )
                }
                .buttonStyle(.plain)
            }
            .tint(AppTheme.textPrimary)
        }
    }

    private var isSelected: Bool {
        state.selectedLibraryID == node.libraryID && state.selectedFolderPaths.contains(node.relativePath)
    }

    private func selectNode() {
        if isCommandPressed {
            state.toggleFolderSelection(in: node.libraryID, relativePath: node.relativePath)
        } else {
            state.selectFolder(in: node.libraryID, relativePath: node.relativePath)
        }
    }

    private var isCommandPressed: Bool {
        #if canImport(AppKit)
        NSApp.currentEvent?.modifierFlags.contains(.command) == true
        #else
        false
        #endif
    }
}

private struct SidebarSelectionRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var trailingText: String? = nil
    let isSelected: Bool
    var indentation: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: indentation, height: 1)
            Image(systemName: systemImage)
                .foregroundStyle(isSelected ? AppTheme.accentLime : AppTheme.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let trailingText {
                AppStatusPill(trailingText, status: isSelected ? .selected : .neutral)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }
}

private struct SidebarMetric: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        AppStatPill(title: title, value: "\(value)", tint: tint)
    }
}
