import PhotoTriageCore
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@MainActor
enum WorkspaceFolderImportController {
    static func useSampleData(with state: AppState) {
        Task { await state.useSampleWorkspace() }
    }

    static func handleFolderDrop(_ urls: [URL], with state: AppState) -> Bool {
        guard !urls.isEmpty else { return false }
        Task { await state.importWorkspaceFolders(from: urls) }
        return true
    }

    static func chooseFolders(using state: AppState) {
#if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.title = "选择照片根目录"
        panel.message = "可多选，也支持后续继续拖入新目录替换工作区。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK else { return }
        Task { await state.importWorkspaceFolders(from: panel.urls) }
#endif
    }
}
