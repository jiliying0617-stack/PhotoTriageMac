import Foundation
import PhotoTriageCore
import PhotoTriageUI
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@main
struct PhotoTriageMacApp: App {
    @StateObject private var state: AppState
    @StateObject private var shortcuts = KeyboardShortcutStore()
    @StateObject private var interactions = InteractionSettingsStore()

    init() {
        let store = UserDefaultsWorkspaceRootsStore()
        store.clearRootPaths()

        _state = StateObject(
            wrappedValue: AppState(
                indexingService: MockIndexingService(),
                inspectionService: MacAssetInspectionService(),
                workspaceRootsStore: store,
                decisionStore: JSONAssetDecisionStore(),
                priorityTagCatalogStore: UserDefaultsPriorityTagCatalogStore(),
                preferredStartupRoots: []
            )
        )
    }

    var body: some Scene {
        WindowGroup("Photo Triage") {
            RootWorkspaceView()
                .environmentObject(state)
                .environmentObject(shortcuts)
                .environmentObject(interactions)
                .frame(minWidth: 1320, minHeight: 860)
                .task {
                    await state.bootstrapIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    clearRuntimeCaches()
                }
        }
        .defaultSize(width: 1480, height: 920)

        Window("对比", id: CompareWindowScene.windowID) {
            CompareWindowView()
                .environmentObject(state)
                .environmentObject(shortcuts)
                .environmentObject(interactions)
        }
        .defaultSize(width: 1500, height: 940)
        .windowResizability(.contentMinSize)

        Settings {
            AppSettingsView()
                .environmentObject(state)
                .environmentObject(shortcuts)
                .environmentObject(interactions)
        }
    }

    private func clearRuntimeCaches() {
        state.clearSessionCaches()
        // Termination may end the process before a newly scheduled task runs.
        PhotoTriageUICaches.clearAll()
    }
}
