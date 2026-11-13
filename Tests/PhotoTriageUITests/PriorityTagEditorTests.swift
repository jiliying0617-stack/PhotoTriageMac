import AppKit
import PhotoTriageCore
import SwiftUI
import Testing
@testable import PhotoTriageUI

@MainActor
struct PriorityTagEditorTests {
    @Test func compareMenuUsesEditedNamesAndTargetsTheNewTagIdentity() throws {
        let view = CompareDragSurfaceView(frame: .zero)
        let custom = PriorityTag(index: 3)
        view.priorityTagDefinitions = [
            PriorityTagDefinition(tag: .p1, name: "皮肤问题"),
            PriorityTagDefinition(tag: custom, name: "手部异常")
        ]
        var selected: PriorityTag?
        view.onApplyPriorityTag = { selected = $0 }
        let menu = view.makeContextMenu()
        #expect(menu.items.contains { $0.title == "皮肤问题（⌥⌘2）" })
        #expect(!menu.items.contains { $0.title == "P1（⌥⌘2）" })
        let item = try #require(menu.items.first { $0.title == "手部异常（⌥⌘4）" })
        let action = try #require(item.action)
        #expect(NSApplication.shared.sendAction(action, to: item.target, from: item))
        #expect(selected == custom)
    }

    @Test func compareMenuOffersTagManagementWithoutFinderTagActions() throws {
        let view = CompareDragSurfaceView(frame: .zero)
        var editRequested = false
        var addRequested = false
        view.onEditPriorityTags = { _ in editRequested = true }
        view.onAddPriorityTag = { _ in addRequested = true }
        let menu = view.makeContextMenu()
        #expect(!menu.items.contains { $0.title.contains("颜色") || $0.title.contains("Finder 标签") || $0.title.contains("红色") })
        for title in ["编辑 P 标签名称…", "新增 P 标签…"] {
            let item = try #require(menu.items.first { $0.title == title })
            #expect(item.isEnabled)
            #expect(NSApplication.shared.sendAction(try #require(item.action), to: item.target, from: item))
        }
        #expect(editRequested && addRequested)
    }

    @Test func tagEditorIsPresentedOnCompareWindowAsASheet() throws {
        let state = AppState(indexingService: MockIndexingService())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil); window.close() }
        PriorityTagEditorPresenter.present(state: state, in: window)
        let sheet = try #require(window.attachedSheet)
        #expect(sheet.title == "编辑 P 标签名称")
        #expect(sheet.contentView != nil)
        window.endSheet(sheet)
    }

    @Test func editorRendersLongNamesAndManyTagsAtCompactWidth() async throws {
        let state = AppState(indexingService: MockIndexingService())
        try state.renamePriorityTag(.p1, to: "皮肤纹理与局部色彩问题")
        for _ in 0..<9 { try state.addPriorityTag() }
        let content = PriorityTagEditorView()
            .environmentObject(state)
            .frame(width: 520, height: 420)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.width == 1040)
        #expect(image.height == 840)
        if let path = ProcessInfo.processInfo.environment["PHOTO_TRIAGE_TAG_PREVIEW"] {
            // ScrollView is AppKit-backed and absent from ImageRenderer output.
            // Host it in a real window for the visual acceptance capture.
            let host = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.orderOut(nil); window.close() }
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: path))
        }
    }
}
