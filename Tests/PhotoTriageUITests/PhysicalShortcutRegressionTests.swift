import AppKit
import Foundation
import PhotoTriageCore
import SwiftUI
import Testing
@testable import PhotoTriageUI

@MainActor
struct PhysicalShortcutRegressionTests {
    @Test func emptyCharactersStillResolveEveryNumberRowAndKeypadChord() throws {
        let rows: [[UInt16]] = [[18, 19, 20, 21, 23, 22, 26, 28, 25, 29],
                                [83, 84, 85, 86, 87, 88, 89, 91, 92, 82]]
        for codes in rows {
            for (index, code) in codes.enumerated() {
                let digit = index == 9 ? 0 : index + 1
                let command = try #require(KeyInput(characters: "", keyCode: code, isCommandPressed: true))
                let plain = try #require(KeyInput(characters: "字", keyCode: code))
                let shift = try #require(KeyInput(characters: "@", keyCode: code, isShiftPressed: true))
                #expect(command.numberKey == digit)
                #expect(command.isAppWideModifiedNumberShortcut)
                #expect(KeyboardShortcutMap.default.priorityTag(for: command) == PriorityTag(index: index))
                #expect(ComparePaneRotationShortcut.index(for: command) == nil)
                if digit != 0 {
                    #expect(KeyboardShortcutMap.default.overlaySlot(for: plain) == digit)
                    #expect(ComparePaneRotationShortcut.index(for: shift) == index)
                }
                let extraModifier = try #require(KeyInput(characters: "2", keyCode: code, isShiftPressed: true, isCommandPressed: true))
                #expect(KeyboardShortcutMap.default.action(for: extraModifier) == nil)
            }
        }
        #expect(KeyInput(characters: "", keyCode: nil) == nil)
        #expect(KeyInput(characters: "2", keyCode: 0)?.numberKey == nil)
        #expect(KeyboardShortcutMap.canonicalKey(for: try #require(KeyInput(characters: "2", keyCode: 0))) == "a")
        #expect(KeyboardShortcutMap.canonicalKey(for: try #require(KeyInput(characters: "2", keyCode: 250))) == "")
    }

    @Test func punctuationAndLettersRecordAndExecuteByPhysicalPosition() throws {
        for code: UInt16 in [0, 12, 24, 27, 30, 33, 39, 41, 42, 43, 44, 47, 50, 69] {
            let input = try #require(KeyInput(characters: "中文", keyCode: code, isCommandPressed: true))
            let chord = KeyboardShortcutMap.canonicalKey(for: input)
            #expect(chord == KeyboardShortcutMap.normalizedKey(chord))
            #expect(chord == "command+" + (try #require(PhysicalShortcutKey.name(for: code))))
        }
        #expect(KeyboardShortcutMap.displayText(for: "command++") == "⌘+")
        #expect(KeyboardShortcutMap.displayText(for: "+") == "+")
    }

    @Test func commandHeldAcrossSuccessiveDownEventsReplacesOnlyCurrentGroup() async throws {
        let state = AppState(indexingService: MockIndexingService())
        await state.reloadWorkspace()
        for _ in 3...9 { try state.addPriorityTag() }
        let ids = Array(state.assets.prefix(2).map(\.id))
        #expect(ids.count == 2)
        state.select(assetID: ids[0])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = KeyEventMonitor.HostView(frame: .zero)
        window.contentView = host
        var delivered: [PriorityTag] = []
        let coordinator = KeyEventMonitor.Coordinator(onKeyDown: { input in
            guard let tag = KeyboardShortcutMap.default.priorityTag(for: input) else { return false }
            delivered.append(tag)
            state.applyPriorityTag(tag, to: ids)
            return true
        }, onKeyUp: { _ in })
        coordinator.hostView = host
        // No Command key-up (or number key-up) between events: each down is independent.
        for (index, code) in [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 19].enumerated() {
            let tag = PriorityTag(index: index == 10 ? 1 : index)
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: .command, timestamp: Double(index), windowNumber: window.windowNumber,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(code)))
            #expect(coordinator.handleKeyDownEvent(event) == nil)
            #expect(delivered.last == tag)
            #expect(state.selectedAssetID == ids[0])
            #expect(state.assets.filter { ids.contains($0.id) }.allSatisfy { $0.priorityTag == tag && $0.appTags.filter { PriorityTag.fromAppTag($0) != nil }.count == 1 })
        }
        #expect(delivered.count == 11)
        #expect(state.assets.filter { !ids.contains($0.id) }.allSatisfy { $0.priorityTag == nil })
    }

    @Test func explicitWindowRoutingCannotBeStolenByAnotherKeyWindow() {
        #expect(!KeyEventWindowRouting.shouldHandle(eventWindowNumber: 2, hostWindowNumber: 1, isHostKeyWindow: true))
        #expect(KeyEventWindowRouting.shouldHandle(eventWindowNumber: nil, hostWindowNumber: 1, isHostKeyWindow: true))
    }

    @Test func invalidCustomChordsCannotOverrideTagsOrSystemCommands() throws {
        let suite = "PhysicalShortcutRegressionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = KeyboardShortcutStore(defaults: defaults)
        for badKey in ["command+2", "command+q", "command+w", "command+c", "command+v"] {
            var keys = store.map.keys
            keys[.nextGroup] = badKey
            store.apply(keys)
            #expect(store.map == .default)
        }
        #expect(KeyboardShortcutMap.duplicateKeys(in: store.map.keys).isEmpty)
        #expect(KeyboardShortcutMap.reservedKeys(in: store.map.keys).isEmpty)
    }

    @Test func repeatedKeyFlagIsPreservedWithoutRequiringCommandRelease() throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
            characters: "@", charactersIgnoringModifiers: "@", isARepeat: true, keyCode: 19))
        let input = try #require(KeyInput(event: event))
        #expect(input.isRepeat)
        #expect(KeyboardShortcutMap.default.priorityTag(for: input) == .p1)
    }

    @Test func command2DoesNotRequireAPreviousModifierEvent() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = KeyEventMonitor.HostView(frame: .zero)
        window.contentView = host
        var received: PriorityTag?
        let coordinator = KeyEventMonitor.Coordinator(onKeyDown: { input in
            received = KeyboardShortcutMap.default.priorityTag(for: input)
            return received != nil
        }, onKeyUp: { _ in })
        coordinator.hostView = host
        let numberDown = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0.1,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 19))
        #expect(coordinator.handleKeyDownEvent(numberDown) == nil)
        #expect(received == .p1)
    }

    @Test func command2AfterModifierReleaseInAnotherWindowDoesNotKeepStaleShift() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = KeyEventMonitor.HostView(frame: .zero)
        window.contentView = host
        var received: PriorityTag?
        let coordinator = KeyEventMonitor.Coordinator(onKeyDown: { input in
            received = KeyboardShortcutMap.default.priorityTag(for: input)
            return received != nil
        }, onKeyUp: { _ in })
        coordinator.hostView = host
        coordinator.start()
        defer { coordinator.stop() }
        let shiftDown = try #require(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .shift,
            timestamp: 1, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56))
        NSApplication.shared.sendEvent(shiftDown)
        // The release happens in a different window and never reaches this coordinator.
        let command2 = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 2, windowNumber: window.windowNumber, context: nil, characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19))
        #expect(coordinator.handleKeyDownEvent(command2) == nil)
        #expect(received == .p1)
    }

    @Test func command2TravelsThroughNativeApplicationDispatchExactlyOnce() throws {
        let app = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = KeyEventMonitor.HostView(frame: .zero)
        window.contentView = host
        var received: [PriorityTag] = []
        let coordinator = KeyEventMonitor.Coordinator(onKeyDown: { input in
            guard let tag = KeyboardShortcutMap.default.priorityTag(for: input) else { return false }
            received.append(tag)
            return true
        }, onKeyUp: { _ in })
        coordinator.hostView = host
        coordinator.start()
        defer { coordinator.stop() }
        for code: UInt16 in [18, 19, 20, 19] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: .command, timestamp: 1, windowNumber: window.windowNumber, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            app.sendEvent(event)
        }
        #expect(received == [.p0, .p1, .p2, .p1])
    }

    @Test func realCompareCanvasSwitchesCurrentGroupWhenCommandStaysHeld() async throws {
        let app = NSApplication.shared
        let state = AppState(indexingService: MockIndexingService())
        await state.reloadWorkspace()
        try state.renamePriorityTag(.p1, to: "P0 力度弱")
        let selected = Array(state.assets.prefix(2).map(\.id))
        #expect(selected.count == 2)
        state.setSelection(assetIDs: Set(selected))
        state.enterCompareMode()
        let ids = state.compareSelectionIDs
        #expect(!ids.isEmpty)
        let suite = "HostedShortcut.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = NSHostingView(rootView: CompareCanvasView()
            .environmentObject(state)
            .environmentObject(KeyboardShortcutStore(defaults: defaults))
            .environmentObject(InteractionSettingsStore(defaults: defaults)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        for (code, tag): (UInt16, PriorityTag) in [(18, .p0), (19, .p1), (20, .p2), (19, .p1)] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: .command, timestamp: 1, windowNumber: window.windowNumber, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            app.sendEvent(event)
            #expect(state.compareSelectionIDs == ids)
            #expect(ids.allSatisfy { id in state.assets.first { $0.id == id }?.priorityTag == tag })
            try await Task.sleep(for: .milliseconds(20))
        }
        state.focusCompareAsset(ids[0])
        try await Task.sleep(for: .milliseconds(50))
        let detailEvent = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 2, windowNumber: window.windowNumber, context: nil,
            characters: "@", charactersIgnoringModifiers: "@", isARepeat: false, keyCode: 19))
        app.sendEvent(detailEvent)
        #expect(state.compareSelectionIDs == ids)
        #expect(ids.allSatisfy { id in state.assets.first { $0.id == id }?.priorityTag == .p1 })
    }

    @Test func workspaceCommand2StillWorksWhileSeparateCompareWindowIsOpen() async throws {
        let app = NSApplication.shared
        let state = AppState(indexingService: MockIndexingService())
        await state.reloadWorkspace()
        let ids = Array(state.assets.prefix(2).map(\.id))
        state.setSelection(assetIDs: Set(ids))
        state.enterCompareMode()
        let suite = "DualWindowShortcut.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcuts = KeyboardShortcutStore(defaults: defaults)
        let interactions = InteractionSettingsStore(defaults: defaults)
        let workspace = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1480, height: 920), styleMask: [.titled], backing: .buffered, defer: false)
        let compare = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        workspace.isReleasedWhenClosed = false
        compare.isReleasedWhenClosed = false
        defer { workspace.contentView = nil; compare.contentView = nil; workspace.close(); compare.close() }
        workspace.contentView = NSHostingView(rootView: RootWorkspaceView().environmentObject(state).environmentObject(shortcuts).environmentObject(interactions))
        compare.contentView = NSHostingView(rootView: CompareCanvasView().environmentObject(state).environmentObject(shortcuts).environmentObject(interactions))
        workspace.contentView?.layoutSubtreeIfNeeded()
        compare.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let compareIDs = state.compareSelectionIDs
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 1, windowNumber: workspace.windowNumber, context: nil,
            characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19))
        app.sendEvent(event)
        #expect(ids.allSatisfy { id in state.assets.first { $0.id == id }?.priorityTag == .p1 })
        #expect(state.compareSelectionIDs == compareIDs)
    }

    @Test func editorFocusAllowsCommand2ButDoesNotStealUnmodifiedTyping() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = KeyEventMonitor.HostView(frame: .zero)
        window.contentView = host
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        host.addSubview(editor)
        #expect(window.makeFirstResponder(editor))
        var inputs: [KeyInput] = []
        let coordinator = KeyEventMonitor.Coordinator(onKeyDown: { input in inputs.append(input); return true }, onKeyUp: { _ in })
        coordinator.hostView = host
        for (code, flags, shouldConsume): (UInt16, NSEvent.ModifierFlags, Bool) in [(0, [], false), (19, .command, true), (19, [], false)] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: flags, timestamp: 1, windowNumber: window.windowNumber, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            #expect((coordinator.handleKeyDownEvent(event) == nil) == shouldConsume)
        }
        #expect(inputs.count == 1)
        #expect(inputs.first.flatMap { KeyboardShortcutMap.default.priorityTag(for: $0) } == .p1)
    }

    @Test func tagEditorSheetBlocksUnderlyingCommand2() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = KeyEventMonitor.HostView(frame: .zero)
        window.contentView = host
        var deliveries = 0
        let coordinator = KeyEventMonitor.Coordinator(onKeyDown: { _ in deliveries += 1; return true }, onKeyUp: { _ in })
        coordinator.hostView = host
        let sheet = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet)
        defer { window.endSheet(sheet); sheet.close() }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 1, windowNumber: window.windowNumber, context: nil,
            characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19))
        #expect(coordinator.handleKeyDownEvent(event) != nil)
        #expect(deliveries == 0)
    }
}
