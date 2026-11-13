import PhotoTriageCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct RootWorkspaceView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var shortcuts: KeyboardShortcutStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var isExporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var exportResultSummary: ExportExecutionSummary?
    @State private var exportResultMessage: String?
    @State private var exportErrorMessage: String?
    @State private var isExportSheetPresented = false
    @State private var exportDirectoryPath = ""
    @State private var exportFolderName = RootWorkspaceView.defaultExportFolderName()
    @State private var shouldExportKeep = true
    @State private var shouldExportReject = true
    @State private var shouldExportPending = true
    @State private var includedPriorityTags: Set<PriorityTag> = []
    @State private var lastExportKeepFolderPath: String?
    @State private var lastExportRejectFolderPath: String?
    @State private var lastExportPendingFolderPath: String?
    @State private var lastExportPriorityTagFolderPaths: [PriorityTag: String] = [:]
    @State private var isTargetedForFolderDrop = false
    @State private var groupJumpText = ""
    @State private var isClearAllTagsConfirmationPresented = false

    public init() {}

    public var body: some View {
        ZStack {
            AppWorkspaceBackdrop()

            NavigationSplitView {
                SourceFoldersSidebar()
                    .navigationSplitViewColumnWidth(min: 280, ideal: 300)
            } content: {
                mainContent
            } detail: {
                InspectorPanelView()
                    .frame(minWidth: 320, idealWidth: 340)
            }
            .navigationSplitViewStyle(.balanced)

            if isTargetedForFolderDrop {
                FolderDropOverlay()
                    .padding(28)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .searchable(text: $state.searchText, prompt: "搜索文件名 / 路径 / 标签")
        .dropDestination(for: URL.self) { urls, location in
            WorkspaceFolderImportController.handleFolderDrop(urls, with: state)
        } isTargeted: { isTargeted in
            isTargetedForFolderDrop = isTargeted
        }
        .onAppear {
            synchronizeCompareWindow(for: state.mode)
        }
        .onChange(of: state.mode) { _, newValue in
            synchronizeCompareWindow(for: newValue)
        }
        .background(
            KeyEventMonitor(
                onKeyDown: handleWorkspaceKeyDown,
                onKeyUp: { _ in }
            )
            .frame(width: 0, height: 0)
        )
        .alert("导出完成", isPresented: exportResultPresented) {
            if let summary = exportResultSummary, summary.keepCount > 0 {
                Button("打开保留目录") {
                    state.revealFolder(at: lastExportKeepFolderPath ?? state.keepFolderPath)
                }
            }
            if let summary = exportResultSummary, summary.rejectCount > 0 {
                Button("打开淘汰目录") {
                    state.revealFolder(at: lastExportRejectFolderPath ?? state.rejectFolderPath)
                }
            }
            if let summary = exportResultSummary, summary.pendingCount > 0, let lastExportPendingFolderPath {
                Button("打开未处理目录") {
                    state.revealFolder(at: lastExportPendingFolderPath)
                }
            }
            ForEach(lastExportPriorityTagFolderPaths.keys.sorted()) { tag in
                if let summary = exportResultSummary, summary.priorityTagSummary.count(for: tag) > 0,
                   let folderPath = lastExportPriorityTagFolderPaths[tag] {
                    Button("打开 \(URL(fileURLWithPath: folderPath).lastPathComponent) 目录") {
                        state.revealFolder(at: folderPath)
                    }
                }
            }
            Button("好") {}
        } message: {
            Text(exportResultMessage ?? "")
        }
        .alert("导出失败", isPresented: exportErrorPresented) {
            Button("好") {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .alert("清除所有标签？", isPresented: $isClearAllTagsConfirmationPresented) {
            Button("取消", role: .cancel) {}
            Button("清除所有标签", role: .destructive) {
                state.clearAllTriageTagsFromWorkspace()
            }
        } message: {
            Text("将所有图片恢复为未处理，并清除所有 P 标签。标签名称设置会保留，不会删除文件。")
        }
        .sheet(isPresented: $isExportSheetPresented) {
            let scopeSummary = state.exportScopeSummary
            ExportOptionsSheet(
                directoryPath: $exportDirectoryPath,
                folderName: $exportFolderName,
                includeKeep: $shouldExportKeep,
                includeReject: $shouldExportReject,
                includePending: $shouldExportPending,
                includedPriorityTags: $includedPriorityTags,
                priorityTagDefinitions: state.priorityTagDefinitions,
                scopeDescription: state.exportScopeDescription,
                scopeAssetCount: scopeSummary.totalCount,
                keepCount: scopeSummary.keepCount,
                rejectCount: scopeSummary.rejectCount,
                pendingCount: scopeSummary.pendingCount,
                priorityTagSummary: scopeSummary.priorityTagSummary,
                isExporting: isExporting,
                progress: state.exportProgress,
                onChooseDirectory: chooseExportDirectory,
                onCancel: {
                    if isExporting { exportTask?.cancel() } else { isExportSheetPresented = false }
                },
                onExport: {
                    exportTask = Task { await exportDecisions() }
                }
            )
        }
    }

    private var mainContent: some View {
        Group {
            if state.isLoading && state.libraries.isEmpty {
                WorkspaceLoadingState()
                    .padding(28)
            } else if state.libraries.isEmpty {
                WorkspaceImportEmptyState(
                    onChooseFolders: chooseFolders,
                    onUseSampleData: {
                        WorkspaceFolderImportController.useSampleData(with: state)
                    }
                )
                .padding(28)
            } else {
                VStack(spacing: 18) {
                    workspaceHeader

                    AssetListView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .appSurface(.panel)
                }
                .padding(20)
            }
        }
        .navigationTitle("工作台")
    }

    private func synchronizeCompareWindow(for mode: WorkspaceMode) {
        if mode == .compare {
            openWindow(id: CompareWindowScene.windowID)
        } else {
            dismissWindow(id: CompareWindowScene.windowID)
        }
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        AppStatusPill("当前任务", status: state.isLoading ? .loading : .focused, systemImage: state.isLoading ? "arrow.triangle.2.circlepath" : "scope")
                        AppStatusPill(state.mode == .compare ? "对比模式" : "网格模式", status: state.mode == .compare ? .selected : .neutral, systemImage: state.mode == .compare ? "rectangle.split.2x1" : "square.grid.2x2")
                    }
                    Text(state.activeFilterDescription)
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                }

                Spacer(minLength: 14)

                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 10) {
                        SettingsLink {
                            Label("设置", systemImage: "gearshape")
                        }
                        .appButtonStyle(.toolbar)

                        Button {
                            Task { await state.requestPreservingWorkspaceReload() }
                        } label: {
                            Label(state.isLoading ? "刷新中…" : "刷新", systemImage: "arrow.clockwise")
                        }
                        .appButtonStyle(.secondary)
                        .disabled(state.isLoading)

                        Button {
                            presentExportSheet()
                        } label: {
                            Label(isExporting ? "导出中…" : "导出", systemImage: "square.and.arrow.up")
                        }
                        .appButtonStyle(.primary)
                        .disabled(isExporting || !hasExportableAssets)

                        Button {
                            isClearAllTagsConfirmationPresented = true
                        } label: {
                            Label("清除所有标签", systemImage: "tag.slash")
                        }
                        .appButtonStyle(.destructive)
                        .disabled(!state.hasAnyTriageTags)

                        Button {
                            if state.mode == .compare {
                                state.exitCompareMode()
                            } else {
                                state.enterCompareMode()
                            }
                        } label: {
                            Label(compareToolbarTitle, systemImage: state.selectedAssetIDs.count >= 2 ? "rectangle.split.2x1" : "photo")
                        }
                        .appButtonStyle(.toolbar)
                        .disabled(state.mode == .grid && state.selectedAssetID == nil)
                    }

                    HStack(spacing: 12) {
                        groupJumpControl
                        Divider()
                            .frame(height: 26)
                        HStack(spacing: 8) {
                            AppStatusPill(state.showUnreviewedOnly ? "只看未处理" : "全部素材", status: state.showUnreviewedOnly ? .pending : .neutral)
                            Toggle("只看未处理", isOn: $state.showUnreviewedOnly)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }
            }


            WorkspaceVisualSummary(
                categorySummary: state.categorySummary,
                categoryFilter: state.categoryFilter,
                priorityTagSummary: state.priorityTagSummary,
                passRate: state.passRate,
                totalCount: state.totalCount,
                allAssetCount: state.allAssetCount,
                selectedCount: state.selectedAssetIDs.count,
                activeFilterDescription: state.activeFilterDescription,
                basenameGroupCount: state.basenameCompareGroupCount,
                currentBasenameGroupNumber: state.currentBasenameCompareGroupNumber,
                onSelectCategory: { state.selectCategoryFilter($0) }
            )
        }
        .appSurface(.panel)
    }

    private var compareToolbarTitle: String {
        if state.mode == .compare {
            return state.isSingleImageCompareMode ? "关闭查看" : "关闭对比"
        }

        return state.selectedAssetIDs.count >= 2 ? "对比" : "查看"
    }

    private var hasExportableAssets: Bool {
        state.exportScopeSummary.totalCount > 0
    }

    private var groupJumpControl: some View {
        HStack(spacing: 8) {
            TextField("组号", text: $groupJumpText)
                .textFieldStyle(.plain)
                .font(.callout.monospacedDigit())
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: 54)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(AppTheme.rowFill, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(AppTheme.borderSoft, lineWidth: 1)
                }
                .onSubmit(jumpToGroup)

            Button("跳转") {
                jumpToGroup()
            }
            .appButtonStyle(.toolbar)
            .disabled(state.basenameCompareGroupCount == 0)

            AppStatusPill("\(state.currentBasenameCompareGroupNumber ?? 0)/\(state.basenameCompareGroupCount)", status: state.basenameCompareGroupCount > 0 ? .focused : .neutral)
        }
    }

    private var exportResultPresented: Binding<Bool> {
        Binding(
            get: { exportResultMessage != nil },
            set: { isPresented in
                if !isPresented {
                    exportResultSummary = nil
                    exportResultMessage = nil
                    lastExportKeepFolderPath = nil
                    lastExportRejectFolderPath = nil
                    lastExportPendingFolderPath = nil
                    lastExportPriorityTagFolderPaths = [:]
                }
            }
        )
    }

    private var exportErrorPresented: Binding<Bool> {
        Binding(
            get: { exportErrorMessage != nil },
            set: { isPresented in
                if !isPresented { exportErrorMessage = nil }
            }
        )
    }

    @MainActor
    private func exportDecisions() async {
        let exportPlan = resolvedExportPlan()
        guard exportPlan.isValid else { return }

        isExporting = true
        defer { isExporting = false }
        let scopeSummary = state.exportScopeSummary

        do {
            let summary = try await state.exportDecisions(
                keepFolderPath: exportPlan.keepFolderPath,
                rejectFolderPath: exportPlan.rejectFolderPath,
                pendingFolderPath: exportPlan.pendingFolderPath,
                priorityTagFolderPaths: exportPlan.priorityTagFolderPaths,
                includeKeep: shouldExportKeep,
                includeReject: shouldExportReject,
                includePending: shouldExportPending,
                includedPriorityTags: includedPriorityTagsForExport()
            )
            exportErrorMessage = nil
            exportResultSummary = summary
            lastExportKeepFolderPath = exportPlan.keepFolderPath
            lastExportRejectFolderPath = exportPlan.rejectFolderPath
            lastExportPendingFolderPath = exportPlan.pendingFolderPath
            lastExportPriorityTagFolderPaths = exportPlan.priorityTagFolderPaths
            isExportSheetPresented = false
            let renameMessage = summary.renamedConflictCount > 0 ? " 其中 \(summary.renamedConflictCount) 张因重名已自动改名。" : ""
            exportResultMessage = exportSummaryMessage(for: summary, scope: scopeSummary) + renameMessage
                + (summary.skippedCount > 0 ? "\n已存在且内容一致，跳过复制：\(summary.skippedCount) 张。" : "")
                + (summary.wasCancelled ? "\n已取消；完成的文件已保留，可重新导出继续。" : "")
                + (summary.failures.isEmpty ? "" : "\n失败 \(summary.failures.count) 项，可重新导出重试：\n" + summary.failures.prefix(5).map { "\($0.sourcePath)：\($0.message)" }.joined(separator: "\n"))
                + (summary.receiptPath.map { "\n详细清单：\($0)" } ?? "")
        } catch {
            exportResultSummary = nil
            exportResultMessage = nil
            exportErrorMessage = error.localizedDescription
        }
    }

    private func presentExportSheet() {
        if exportDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            exportDirectoryPath = defaultExportDirectoryPath()
        }
        if exportFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            exportFolderName = Self.defaultExportFolderName()
        }
        let scopeSummary = state.exportScopeSummary
        shouldExportKeep = scopeSummary.keepCount > 0
        shouldExportReject = scopeSummary.rejectCount > 0
        shouldExportPending = scopeSummary.pendingCount > 0
        includedPriorityTags = Set(state.priorityTags.filter { scopeSummary.priorityTagSummary.count(for: $0) > 0 })
        isExportSheetPresented = true
    }

    private func chooseExportDirectory() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        if !exportDirectoryPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: exportDirectoryPath, isDirectory: true)
        }

        if panel.runModal() == .OK, let url = panel.url {
            exportDirectoryPath = url.standardizedFileURL.path
        }
        #endif
    }

    private func defaultExportDirectoryPath() -> String {
        if let firstLibraryPath = state.libraries.first?.path {
            return URL(fileURLWithPath: firstLibraryPath, isDirectory: true)
                .deletingLastPathComponent()
                .path
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .path
    }

    private func resolvedExportPlan() -> ExportPlan {
        let directory = exportDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = sanitizedExportFolderName(exportFolderName)
        guard !directory.isEmpty, !folderName.isEmpty else {
            return ExportPlan(
                keepFolderPath: "",
                rejectFolderPath: "",
                pendingFolderPath: "",
                priorityTagFolderPaths: [:],
                isValid: false
            )
        }

        let baseURL = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        let priorityTagFolderPaths = PriorityTagExportFolders.paths(
            under: baseURL,
            definitions: state.priorityTagDefinitions
        )
        return ExportPlan(
            keepFolderPath: baseURL.appendingPathComponent("保留", isDirectory: true).path,
            rejectFolderPath: baseURL.appendingPathComponent("淘汰", isDirectory: true).path,
            pendingFolderPath: baseURL.appendingPathComponent("未处理", isDirectory: true).path,
            priorityTagFolderPaths: priorityTagFolderPaths,
            isValid: shouldExportKeep
                || shouldExportReject
                || shouldExportPending
                || !includedPriorityTagsForExport().isEmpty
        )
    }

    private func includedPriorityTagsForExport() -> Set<PriorityTag> {
        let prioritySummary = state.exportScopeSummary.priorityTagSummary
        return Set(includedPriorityTags.filter { prioritySummary.count(for: $0) > 0 })
    }

    private func exportSummaryMessage(for summary: ExportExecutionSummary, scope: AssetCategorySummary) -> String {
        let tagSummary = summary.priorityTagSummary
        let passRate = formattedPercent(scope.totalCount > 0 ? Double(scope.totalCount - scope.rejectCount) / Double(scope.totalCount) : 0)
        let priorityText = state.priorityTags.filter { tagSummary.count(for: $0) > 0 }.map { tag in
            "\(state.priorityTagDisplayName(tag)) \(tagSummary.count(for: tag))（\(formattedPercent(scope.priorityTagSummary.ratio(for: tag, totalCount: scope.totalCount)))）"
        }.joined(separator: " / ")
        return "已导出 \(summary.exportedCount) 份文件：保留 \(summary.keepCount) / 淘汰 \(summary.rejectCount) / 未处理 \(summary.pendingCount)，通过率 \(passRate)。P 标签：\(priorityText.isEmpty ? "无" : priorityText)。"
    }

    private func sanitizedExportFolderName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        return name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func defaultExportFolderName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "筛图导出-\(formatter.string(from: Date()))"
    }

    private func jumpToGroup() {
        guard let number = Int(groupJumpText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        state.jumpToBasenameCompareGroup(number: number, enterCompare: false)
    }

    private func handleWorkspaceKeyDown(_ input: KeyInput) -> Bool {
        // Workspace and comparison are separate windows. KeyEventMonitor routes
        // by the actual host window, even while the other window stays open.

        if let tag = shortcuts.action(for: input, scope: .workspace)?.priorityTag {
            guard state.priorityTags.contains(tag) else { return true }
            guard !input.isRepeat else { return true }
            state.applyPriorityTag(tag, to: workspaceFocusedAssetIDs)
            return true
        }

        switch shortcuts.action(for: input, scope: .workspace) {
        case .some(.keep):
            applyRatingAndAdvance(.keep)
            return true
        case .some(.pending):
            applyRatingAndAdvance(.pending)
            return true
        case .some(.reject):
            applyRatingAndAdvance(.reject)
            return true
        case .some(.clearAllTags):
            clearAllTagsAndAdvance()
            return true
        case .some(.enterCompare):
            guard state.selectedAssetIDs.count >= 2 else { return true }
            state.enterCompareMode()
            return true
        case .some(.openFocusedItem):
            state.enterCompareMode()
            return true
        case .some(.previousItemLeft), .some(.previousItemUp):
            state.moveSelection(delta: -1)
            return true
        case .some(.nextItemRight), .some(.nextItemDown):
            state.moveSelection(delta: 1)
            return true
        default:
            return false
        }
    }

    private func applyRatingAndAdvance(_ rating: RatingState) {
        let target = workspaceFocusedAssetIDs
        guard !target.isEmpty else { return }
        let shouldAdvance = target.count <= 1
        let nextAssetID = shouldAdvance
            ? target.first.flatMap { state.visibleAssetID(after: $0) }
            : nil
        state.applyRating(rating, to: target)
        if let nextAssetID, !target.contains(nextAssetID) {
            state.select(assetID: nextAssetID)
        }
    }

    private func clearAllTagsAndAdvance() {
        let target = workspaceFocusedAssetIDs
        guard !target.isEmpty else { return }
        let shouldAdvance = target.count <= 1
        let nextAssetID = shouldAdvance
            ? target.first.flatMap { state.visibleAssetID(after: $0) }
            : nil
        state.clearAllTriageTags(from: target)
        if let nextAssetID, !target.contains(nextAssetID) {
            state.select(assetID: nextAssetID)
        }
    }

    private var workspaceFocusedAssetIDs: [UUID] {
        if !state.selectedAssetIDs.isEmpty {
            return Array(state.selectedAssetIDs)
        }
        return state.selectedAssetID.map { [$0] } ?? []
    }

    private func chooseFolders() {
        WorkspaceFolderImportController.chooseFolders(using: state)
    }
}

enum WorkspaceCompareShortcut {
    static func shouldEnterCompare(
        for input: KeyInput,
        selectedCount: Int,
        shortcuts: KeyboardShortcutMap = .default
    ) -> Bool {
        guard selectedCount >= 2,
              shortcuts.action(for: input, scope: .workspace) == .enterCompare else {
            return false
        }
        return true
    }
}

private struct ExportPlan {
    let keepFolderPath: String
    let rejectFolderPath: String
    let pendingFolderPath: String
    let priorityTagFolderPaths: [PriorityTag: String]
    let isValid: Bool
}

private func formattedPercent(_ value: Double) -> String {
    String(format: "%.1f%%", value * 100)
}

private struct ExportOptionsSheet: View {
    @Binding var directoryPath: String
    @Binding var folderName: String
    @Binding var includeKeep: Bool
    @Binding var includeReject: Bool
    @Binding var includePending: Bool
    @Binding var includedPriorityTags: Set<PriorityTag>
    let priorityTagDefinitions: [PriorityTagDefinition]
    let scopeDescription: String
    let scopeAssetCount: Int
    let keepCount: Int
    let rejectCount: Int
    let pendingCount: Int
    let priorityTagSummary: PriorityTagSummary
    let isExporting: Bool
    let progress: ExportProgress?
    let onChooseDirectory: () -> Void
    let onCancel: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                AppSectionTitle("导出设置", subtitle: "选择批次文件夹和导出范围")
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textSecondary)
                .disabled(isExporting)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("来源：\(scopeDescription)")
                    .lineLimit(2)
                    .help(scopeDescription)
                Text("当前目录范围共 \(scopeAssetCount) 张，按下方勾选分类导出。")
            }
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)

            VStack(alignment: .leading, spacing: 12) {
                ExportFieldLabel("目录")
                HStack(spacing: 10) {
                    Text(directoryPath.isEmpty ? "未选择" : directoryPath)
                        .font(.callout)
                        .foregroundStyle(directoryPath.isEmpty ? AppTheme.textSecondary : AppTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(AppTheme.rowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button {
                        onChooseDirectory()
                    } label: {
                        Label("选择", systemImage: "folder")
                    }
                    .appButtonStyle(.toolbar)
                    .disabled(isExporting)
                }

                ExportFieldLabel("批次文件夹名")
                TextField("导出文件夹名", text: $folderName)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.rowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.borderSoft, lineWidth: 1)
                    }
                    .disabled(isExporting)
            }

            VStack(alignment: .leading, spacing: 10) {
                ExportFieldLabel("评分导出")
                Toggle("保留 \(keepCount)", isOn: $includeKeep)
                    .disabled(keepCount == 0 || isExporting)
                Toggle("淘汰 \(rejectCount)", isOn: $includeReject)
                    .disabled(rejectCount == 0 || isExporting)
                Toggle("未处理 \(pendingCount)", isOn: $includePending)
                    .disabled(pendingCount == 0 || isExporting)
            }
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 10) {
                ExportFieldLabel("P 标签导出")
                ScrollView {
                    LazyVGrid(columns: tagColumns, alignment: .leading, spacing: 10) {
                        ForEach(priorityTagDefinitions) { definition in
                            Toggle("\(definition.name) \(priorityTagSummary.count(for: definition.tag))", isOn: Binding(
                                get: { includedPriorityTags.contains(definition.tag) },
                                set: { enabled in
                                    if enabled { includedPriorityTags.insert(definition.tag) }
                                    else { includedPriorityTags.remove(definition.tag) }
                                }
                            ))
                            .disabled(priorityTagSummary.count(for: definition.tag) == 0 || isExporting)
                            .help("导出到 \(definition.name) 文件夹")
                        }
                    }
                }
                .frame(height: min(120, CGFloat((priorityTagDefinitions.count + 1) / 2) * 32))
            }
            .toggleStyle(.checkbox)

            Text("导出会复制原文件，并保留素材目录中的原始子目录结构。")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            if isExporting, let progress {
                ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
                Text("已处理 \(progress.completed) / \(progress.total)")
                    .font(.caption.monospacedDigit())
            }

            HStack {
                Spacer()
                Button(isExporting ? "停止导出" : "取消", action: onCancel)
                    .appButtonStyle(.toolbar)
                Button {
                    onExport()
                } label: {
                    Label(isExporting ? "导出中…" : "开始导出", systemImage: "square.and.arrow.up")
                }
                .appButtonStyle(.primary)
                .disabled(!canExport)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(AppTheme.panelFill)
    }

    private var canExport: Bool {
        !isExporting
        && !directoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (
            (includeKeep && keepCount > 0)
            || (includeReject && rejectCount > 0)
            || (includePending && pendingCount > 0)
            || includedPriorityTags.contains(where: { priorityTagSummary.count(for: $0) > 0 })
        )
    }

    private var tagColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

}

private struct ExportFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
    }
}

private struct WorkspaceImportEmptyState: View {
    let onChooseFolders: () -> Void
    let onUseSampleData: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(AppTheme.accentLime)

            VStack(spacing: 10) {
                Text("拖入照片文件夹")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textOnDark)
                Text("拖进来，或直接选择。")
                    .font(.body)
                    .foregroundStyle(AppTheme.textOnDarkSecondary)
            }

            HStack(spacing: 12) {
                Button("选择文件夹", action: onChooseFolders)
                    .appButtonStyle(.primary)
                Button("示例数据", action: onUseSampleData)
                    .appButtonStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appSurface(.hero)
        .colorScheme(.dark)
    }
}

private struct WorkspaceVisualSummary: View {
    @EnvironmentObject private var state: AppState
    @State private var isEditingTags = false
    let categorySummary: AssetCategorySummary
    let categoryFilter: AssetCategoryFilter
    let priorityTagSummary: PriorityTagSummary
    let passRate: Double
    let totalCount: Int
    let allAssetCount: Int
    let selectedCount: Int
    let activeFilterDescription: String
    let basenameGroupCount: Int
    let currentBasenameGroupNumber: Int?
    let onSelectCategory: (AssetCategoryFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                AppStatPill(title: "通过率", value: passPercent, tint: passRate >= 0.8 ? AppTheme.success : AppTheme.warning)
                AppStatPill(title: "已处理", value: processedPercent, tint: processedRate >= 0.8 ? AppTheme.success : AppTheme.warning)
                AppStatPill(title: "当前结果", value: "\(totalCount)", tint: AppTheme.accentLime)
                AppStatPill(title: "已选", value: "\(selectedCount)", tint: selectedCount > 0 ? AppTheme.accentLime : AppTheme.textSecondary)
                AppStatPill(title: "对比组", value: "\(currentBasenameGroupNumber ?? 0)/\(basenameGroupCount)", tint: basenameGroupCount > 0 ? AppTheme.accentPeach : AppTheme.textSecondary)
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                ForEach(ratingFilterCards) { card in
                    WorkspaceFilterCard(
                        card: card,
                        isSelected: categoryFilter == card.filter,
                        action: { onSelectCategory(card.filter) }
                    )
                }
            }

            HStack {
                Spacer()
                Button { isEditingTags = true } label: {
                    Label("编辑标签", systemImage: "pencil")
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $isEditingTags) {
                    PriorityTagEditorView().environmentObject(state)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(priorityFilterCards) { card in
                    WorkspaceFilterCard(
                        card: card,
                        isSelected: categoryFilter == card.filter,
                        action: { onSelectCategory(card.filter) }
                    )
                }
            }
        }
    }

    private var processedRate: Double {
        guard categorySummary.totalCount > 0 else { return 0 }
        return Double(categorySummary.keepCount + categorySummary.rejectCount) / Double(categorySummary.totalCount)
    }

    private var processedPercent: String {
        formattedPercent(processedRate)
    }

    private var passPercent: String {
        formattedPercent(passRate)
    }

    private var ratingFilterCards: [WorkspaceFilterCardData] {
        [
            WorkspaceFilterCardData(
                filter: .all,
                title: "全部图片",
                count: categorySummary.totalCount,
                detail: "当前范围",
                tint: AppTheme.accentLime
            ),
            WorkspaceFilterCardData(
                filter: .rating(.keep),
                title: "保留",
                count: categorySummary.keepCount,
                detail: scopedPercentText(categorySummary.keepCount),
                tint: AppTheme.success
            ),
            WorkspaceFilterCardData(
                filter: .rating(.reject),
                title: "淘汰",
                count: categorySummary.rejectCount,
                detail: scopedPercentText(categorySummary.rejectCount),
                tint: AppTheme.danger
            ),
            WorkspaceFilterCardData(
                filter: .rating(.pending),
                title: "未处理",
                count: categorySummary.pendingCount,
                detail: scopedPercentText(categorySummary.pendingCount),
                tint: AppTheme.warning
            ),
        ]
    }

    private var priorityFilterCards: [WorkspaceFilterCardData] {
        state.priorityTags.map(priorityCard)
    }

    private func priorityCard(_ tag: PriorityTag) -> WorkspaceFilterCardData {
        WorkspaceFilterCardData(
            filter: .priority(tag),
            title: state.priorityTagDisplayName(tag),
            count: categorySummary.priorityTagSummary.count(for: tag),
            detail: "全部 \(percentText(priorityTagSummary.count(for: tag), total: allAssetCount))",
            tint: TagPill.tintColor(for: tag)
        )
    }

    private func scopedPercentText(_ count: Int) -> String {
        "范围 \(percentText(count, total: categorySummary.totalCount))"
    }

    private func percentText(_ count: Int, total: Int) -> String {
        guard total > 0 else { return formattedPercent(0) }
        return formattedPercent(Double(count) / Double(total))
    }
}

private struct WorkspaceFilterCardData: Identifiable {
    let filter: AssetCategoryFilter
    let title: String
    let count: Int
    let detail: String
    let tint: Color

    var id: AssetCategoryFilter { filter }
}

private struct WorkspaceFilterCard: View {
    let card: WorkspaceFilterCardData
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle().fill(card.tint).frame(width: 7, height: 7)
                    Text(card.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 3)
                    Text("\(card.count)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Text(card.detail)
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(isSelected ? card.tint : AppTheme.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? card.tint.opacity(0.18) : AppTheme.rowFill.opacity(0.55))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? card.tint.opacity(0.78) : AppTheme.borderSoft, lineWidth: isSelected ? 1.3 : 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(card.title)
    }
}

private struct WorkspaceLoadingState: View {
    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(AppTheme.accentLime)

            VStack(spacing: 8) {
                Text("正在导入")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textOnDark)
                Text("稍等一下")
                    .font(.body)
                    .foregroundStyle(AppTheme.textOnDarkSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appSurface(.hero)
        .colorScheme(.dark)
    }
}

private struct FolderDropOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.white)
            Text("松手导入")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textOnDark)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [12, 10]))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .shadow(color: AppTheme.accentLime.opacity(0.28), radius: 30, y: 12)
    }
}
