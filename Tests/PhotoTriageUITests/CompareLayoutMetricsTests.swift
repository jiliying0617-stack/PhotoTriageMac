import Foundation
import AppKit
import SwiftUI
import PhotoTriageCore
import Testing
@testable import PhotoTriageUI

struct CompareLayoutMetricsTests {
    @Test
    func commandNumberPriorityTagShortcutsDoNotConflictWithNumberedOverlays() {
        let command1 = KeyInput(characters: "1", isCommandPressed: true)!
        let command7 = KeyInput(characters: "7", isCommandPressed: true)!
        let command8 = KeyInput(characters: "8", isCommandPressed: true)!
        let command9 = KeyInput(characters: "9", isCommandPressed: true)!

        #expect(KeyboardShortcutMap.default.priorityTag(for: command1) == .p0)
        #expect(KeyboardShortcutMap.default.priorityTag(for: command7) == PriorityTag(index: 6))
        #expect(KeyboardShortcutMap.default.priorityTag(for: command8) == PriorityTag(index: 7))
        #expect(KeyboardShortcutMap.default.priorityTag(for: command9) == PriorityTag(index: 8))
        #expect(CompareKeyboardAction.action(for: command1) == .applyPriorityTag(.p0))
        #expect(KeyboardShortcutMap.default.priorityTag(for: KeyInput(characters: "1")!) == nil)
        #expect(command1.isAppWideModifiedNumberShortcut)
        #expect(KeyInput(characters: "1", isShiftPressed: true)!.isAppWideModifiedNumberShortcut)
        #expect(!KeyInput(characters: "1")!.isAppWideModifiedNumberShortcut)
        #expect(!KeyInput(characters: "1", isShiftPressed: true, isCommandPressed: true)!.isAppWideModifiedNumberShortcut)
    }

    @Test
    func optionCommandNumberPriorityTagShortcutsTargetOnlyTheHoveredImage() throws {
        let optionCommand1 = try #require(KeyInput(
            characters: "1",
            keyCode: 18,
            isOptionPressed: true,
            isCommandPressed: true
        ))
        let optionCommand0 = try #require(KeyInput(
            characters: "0",
            keyCode: 29,
            isOptionPressed: true,
            isCommandPressed: true
        ))

        #expect(CompareSingleImagePriorityShortcut.tag(for: optionCommand1) == .p0)
        #expect(CompareSingleImagePriorityShortcut.tag(for: optionCommand0) == PriorityTag(index: 9))
        #expect(CompareSingleImagePriorityShortcut.tag(for: KeyInput(characters: "1", isCommandPressed: true)!) == nil)
        #expect(CompareSingleImagePriorityShortcut.tag(for: KeyInput(characters: "1", isOptionPressed: true)!) == nil)
        #expect(CompareSingleImagePriorityShortcut.tag(for: KeyInput(characters: "1", isShiftPressed: true, isOptionPressed: true, isCommandPressed: true)!) == nil)
        #expect(KeyboardShortcutMap.default.action(for: optionCommand1, scope: .compare) == nil)
    }

    @Test
    func everyNumberShortcutUsesThePhysicalNumberRowKey() {
        let physical1WithLayoutCharacter = KeyInput(characters: "&", keyCode: 18)!
        let physical9WithLayoutCharacter = KeyInput(characters: "ç", keyCode: 25)!

        #expect(KeyboardShortcutMap.default.overlaySlot(for: physical1WithLayoutCharacter) == 1)
        #expect(KeyboardShortcutMap.default.overlaySlot(for: physical9WithLayoutCharacter) == 9)
        #expect(
            KeyboardShortcutMap.default.priorityTag(
                for: KeyInput(characters: "æ", keyCode: 19, isCommandPressed: true)!
            ) == .p1
        )
    }

    @Test
    func allPriorityNumberShortcutsUsePhysicalKeysInBothViews() throws {
        let physicalCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
        for (index, keyCode) in physicalCodes.enumerated() {
            let input = try #require(KeyInput(characters: "字", keyCode: keyCode, isCommandPressed: true))
            let tag = PriorityTag(index: index)
            let action = try #require(KeyboardShortcutAction.priorityAction(for: tag))
            #expect(KeyboardShortcutMap.default.action(for: input, scope: .workspace) == action)
            #expect(KeyboardShortcutMap.default.action(for: input, scope: .compare) == action)
            #expect(CompareKeyboardAction.action(for: input) == .applyPriorityTag(tag))
            #expect(input.isAppWideModifiedNumberShortcut)
        }
        #expect(KeyboardShortcutMap.duplicateKeys(in: KeyboardShortcutMap.default.keys).isEmpty)
        #expect(KeyboardShortcutAction.allCases.allSatisfy { !$0.rawValue.hasPrefix("finderTag") })
    }

    @Test
    func modifierShortcutsCanBeCustomizedAndStillUsePhysicalKeys() throws {
        var keys = KeyboardShortcutMap.default.keys
        keys[.priorityP0] = "control+t"
        keys[.rotatePane1] = "command+k"
        let map = KeyboardShortcutMap(keys: keys)

        let customTag = try #require(KeyInput(characters: "t", keyCode: 17, isControlPressed: true))
        let customRotation = try #require(KeyInput(characters: "k", keyCode: 40, isCommandPressed: true))

        #expect(
            map.priorityTag(for: customTag) == .p0
        )
        #expect(ComparePaneRotationShortcut.index(for: customRotation, shortcuts: map) == 0)
        #expect(map.priorityTag(for: KeyInput(characters: "1", isCommandPressed: true)!) == nil)
    }

    @Test
    func sameShortcutCanBeUsedInSeparateWorkspaceAndCompareContexts() throws {
        var keys = KeyboardShortcutMap.default.keys
        keys[.enterCompare] = "z"
        keys[.nextGroup] = "z"
        let map = KeyboardShortcutMap(keys: keys)
        let input = try #require(KeyInput(characters: "z"))

        #expect(!KeyboardShortcutMap.duplicateKeys(in: keys).contains("z"))
        #expect(map.action(for: input, scope: .workspace) == .enterCompare)
        #expect(map.action(for: input, scope: .compare) == .nextGroup)
    }

    @Test
    @MainActor
    func interactionSettingsPersistAndReverseZoomDirection() throws {
        let suiteName = "PhotoTriageInteractionSettings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = InteractionSettingsStore(defaults: defaults)
        #expect(first.wheelZoomEnabled)
        #expect(first.adjustedZoomDelta(12) == 12)

        first.wheelZoomEnabled = false
        first.naturalScrollZoom = false

        let reloaded = InteractionSettingsStore(defaults: defaults)
        #expect(!reloaded.wheelZoomEnabled)
        #expect(!reloaded.naturalScrollZoom)
        #expect(reloaded.adjustedZoomDelta(12) == -12)
    }

    @Test
    func keyEventWindowRoutingFallsBackToTheKeyWindowWhenAppKitOmitsTheEventWindow() {
        #expect(
            KeyEventWindowRouting.shouldHandle(
                eventWindowNumber: nil,
                hostWindowNumber: 41,
                isHostKeyWindow: true
            )
        )
        #expect(
            !KeyEventWindowRouting.shouldHandle(
                eventWindowNumber: nil,
                hostWindowNumber: 41,
                isHostKeyWindow: false
            )
        )
        #expect(
            KeyEventWindowRouting.shouldHandle(
                eventWindowNumber: 41,
                hostWindowNumber: 41,
                isHostKeyWindow: false
            )
        )
        #expect(
            !KeyEventWindowRouting.shouldHandle(
                eventWindowNumber: 42,
                hostWindowNumber: 41,
                isHostKeyWindow: false
            )
        )
    }

    @Test
    @MainActor
    func keyEventMonitorStartsWhenItsHostActuallyJoinsAWindow() {
        let coordinator = KeyEventMonitor.Coordinator(onKeyDown: { _ in false }, onKeyUp: { _ in })
        let host = KeyEventMonitor.HostView(frame: .zero)
        host.monitorCoordinator = coordinator
        coordinator.hostView = host
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        #expect(!coordinator.isRunning)
        window.contentView = host
        #expect(coordinator.isRunning)
        window.contentView = NSView(frame: .zero)
        #expect(!coordinator.isRunning)
    }

    @Test
    func spaceEntersCompareOnlyForMultipleThumbnailSelections() {
        let space = KeyInput(characters: " ")!

        #expect(WorkspaceCompareShortcut.shouldEnterCompare(for: space, selectedCount: 2))
        #expect(WorkspaceCompareShortcut.shouldEnterCompare(for: space, selectedCount: 9))
        #expect(!WorkspaceCompareShortcut.shouldEnterCompare(for: space, selectedCount: 1))
        #expect(
            !WorkspaceCompareShortcut.shouldEnterCompare(
                for: KeyInput(characters: " ", isShiftPressed: true)!,
                selectedCount: 3
            )
        )
    }

    @Test
    func shiftNumberRotatesMatchingComparePaneWithoutConflictingWithOtherNumberShortcuts() throws {
        let realShift1Event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .shift,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "!",
                charactersIgnoringModifiers: "!",
                isARepeat: false,
                keyCode: 18
            )
        )

        #expect(ComparePaneRotationShortcut.index(for: KeyInput(characters: "1", isShiftPressed: true)!) == 0)
        #expect(ComparePaneRotationShortcut.index(for: try #require(KeyInput(event: realShift1Event))) == 0)
        #expect(ComparePaneRotationShortcut.index(for: KeyInput(characters: "!", keyCode: 18, isShiftPressed: true)!) == 0)
        #expect(ComparePaneRotationShortcut.index(for: KeyInput(characters: "@", keyCode: 19, isShiftPressed: true)!) == 1)
        #expect(ComparePaneRotationShortcut.index(for: KeyInput(characters: "#", keyCode: 20, isShiftPressed: true)!) == 2)
        #expect(ComparePaneRotationShortcut.index(for: KeyInput(characters: "5", isShiftPressed: true)!) == 4)
        #expect(ComparePaneRotationShortcut.index(for: KeyInput(characters: "9", isShiftPressed: true)!) == 8)
        #expect(ComparePaneRotationShortcut.index(for: KeyInput(characters: "1")!) == nil)
        #expect(ComparePaneRotationShortcut.index(for: KeyInput(characters: "1", isCommandPressed: true)!) == nil)
        #expect(CompareKeyboardAction.action(for: "1") == .numberedOverlay(1))
        #expect(KeyInput(characters: "!", keyCode: 18, isShiftPressed: true)!.isAppWideModifiedNumberShortcut)
    }

    @Test
    @MainActor
    func compareImageContextMenuProvidesOnlyPriorityTagShortcuts() throws {
        let view = CompareDragSurfaceView(frame: .zero)
        view.priorityTagDefinitions = (0...9).map { PriorityTagDefinition(tag: PriorityTag(index: $0)) }
        let menu = view.makeContextMenu()
        for index in 0...9 {
            let digit = index == 9 ? 0 : index + 1
            #expect(menu.items.contains { $0.title == "P\(index)（⌥⌘\(digit)）" })
        }
        #expect(menu.items.allSatisfy { $0.submenu == nil })
        #expect(!menu.items.contains { $0.title.contains("Finder 标签") || $0.title.contains("红色") })
    }

    @Test
    func compareWindowUsesDesktopViewerFootprint() {
        let size = CompareLayoutMetrics.compareWindowDefaultSize()
        let minimumSize = CompareLayoutMetrics.compareWindowMinimumSize()

        #expect(size.width == 1500)
        #expect(size.height == 940)
        #expect(minimumSize.width == 1180)
        #expect(minimumSize.height == 760)
    }

    @Test
    func overlayOpacityIsFullyOpaqueForSeamlessCompare() {
        #expect(CompareLayoutMetrics.overlayOpacity == 1)
    }

    @Test
    func compareRenderResolutionMatchesRetinaPixelsAndCanReachOriginalResolution() {
        let original = CGSize(width: 5464, height: 8192)

        let fittedResolution = CompareLayoutMetrics.requiredRenderPixelDimension(
            originalPixelSize: original,
            renderedPointSize: CGSize(width: 900, height: 1350),
            displayScale: 2
        )
        let zoomedResolution = CompareLayoutMetrics.requiredRenderPixelDimension(
            originalPixelSize: original,
            renderedPointSize: CGSize(width: 3600, height: 5400),
            displayScale: 2
        )

        #expect(fittedResolution == 3072)
        #expect(zoomedResolution == 8192)
    }

    @Test
    func compareRenderResolutionNeverUpscalesBeyondOriginalPixels() {
        let resolution = CompareLayoutMetrics.requiredRenderPixelDimension(
            originalPixelSize: CGSize(width: 1200, height: 800),
            renderedPointSize: CGSize(width: 2000, height: 1400),
            displayScale: 2
        )

        #expect(resolution == 1200)
    }

    @Test
    func cyclicOverlayUsesExclusivePreloadedLayerVisibility() {
        #expect(
            CompareCyclicOverlayBehavior.layerVisibility(isActive: false)
                == CompareOverlayLayerVisibility(
                    persistentOverlayIsVisible: true,
                    cyclicOverlayIsVisible: false
                )
        )
        #expect(
            CompareCyclicOverlayBehavior.layerVisibility(isActive: true)
                == CompareOverlayLayerVisibility(
                    persistentOverlayIsVisible: false,
                    cyclicOverlayIsVisible: true
                )
        )
    }

    @Test
    func cyclicOverlayIgnoresKeyRepeatStateChanges() {
        #expect(
            CompareCyclicOverlayBehavior.shouldApplyStateChange(
                currentValue: false,
                requestedValue: true,
                assetCount: 3
            )
        )
        #expect(
            !CompareCyclicOverlayBehavior.shouldApplyStateChange(
                currentValue: true,
                requestedValue: true,
                assetCount: 3
            )
        )
        #expect(
            !CompareCyclicOverlayBehavior.shouldApplyStateChange(
                currentValue: false,
                requestedValue: true,
                assetCount: 1
            )
        )
    }

    @Test
    func spaceUsesSameKeyboardActionAsDownArrowForNextGroup() {
        #expect(CompareKeyboardAction.action(for: " ") == .nextGroup)
        #expect(CompareKeyboardAction.action(for: "\u{F701}") == .nextGroup)
    }

    @Test
    func compareKeyboardActionKeepsExistingShortcutsDistinct() {
        #expect(CompareKeyboardAction.action(for: "\u{1B}") == .showOverview)
        #expect(CompareKeyboardAction.action(for: "a") == .rateKeep)
        #expect(CompareKeyboardAction.action(for: "s") == .ratePending)
        #expect(CompareKeyboardAction.action(for: "d") == .rateReject)
        #expect(CompareKeyboardAction.action(for: "x") == .clearAllTags)
        #expect(CompareKeyboardAction.action(for: "b") == .previousGroup)
        #expect(CompareKeyboardAction.action(for: "\u{F700}") == .previousGroup)
        #expect(CompareKeyboardAction.action(for: "q") == .beginCyclicOverlay)
        #expect(CompareKeyboardAction.action(for: "0") == .toggleToleranceView)
        #expect(CompareKeyboardAction.action(for: "w") == .none)
        #expect(CompareKeyboardAction.action(for: "e") == .none)
        #expect(CompareKeyboardAction.action(for: "r") == .none)
        #expect(CompareKeyboardAction.action(for: KeyInput(characters: "1", isCommandPressed: true)!) == .applyPriorityTag(.p0))
        #expect(CompareKeyboardAction.action(for: KeyInput(characters: "2", isCommandPressed: true)!) == .applyPriorityTag(.p1))
        #expect(CompareKeyboardAction.action(for: KeyInput(characters: "3", isCommandPressed: true)!) == .applyPriorityTag(.p2))
        #expect(CompareKeyboardAction.action(for: "1") == .numberedOverlay(1))
        #expect(CompareKeyboardAction.action(for: "4") == .numberedOverlay(4))
        #expect(CompareKeyboardAction.action(for: "9") == .numberedOverlay(9))
    }

    @Test
    func compareKeyboardActionUsesCustomShortcutMap() {
        var keys = KeyboardShortcutMap.default.keys
        keys[.keep] = "k"
        keys[.priorityP0] = "p"
        keys[.toleranceView] = "t"
        keys[.overlay9] = "v"
        let map = KeyboardShortcutMap(keys: keys)

        #expect(CompareKeyboardAction.action(for: "k", shortcuts: map) == .rateKeep)
        #expect(CompareKeyboardAction.action(for: "p", shortcuts: map) == .applyPriorityTag(.p0))
        #expect(CompareKeyboardAction.action(for: "t", shortcuts: map) == .toggleToleranceView)
        #expect(CompareKeyboardAction.action(for: "v", shortcuts: map) == .numberedOverlay(9))
        #expect(CompareKeyboardAction.action(for: "a", shortcuts: map) == .none)
    }

    @Test
    func shortcutMapDetectsDuplicateKeys() {
        var keys = KeyboardShortcutMap.default.keys
        keys[.keep] = "q"
        keys[.cyclicOverlay] = "q"

        #expect(KeyboardShortcutMap.duplicateKeys(in: keys) == ["q"])
    }

    @Test
    func compareKeyboardActionSupportsFocusedAndBatchRotation() throws {
        #expect(CompareKeyboardAction.action(for: "r") == .none)
        #expect(CompareKeyboardAction.action(for: try #require(KeyInput(characters: "r", isShiftPressed: true))) == .rotateFocusedCounterclockwise)
        #expect(CompareKeyboardAction.action(for: try #require(KeyInput(characters: "r", isOptionPressed: true))) == .rotateSelectionClockwise)
        #expect(CompareKeyboardAction.action(for: try #require(KeyInput(characters: "r", isShiftPressed: true, isOptionPressed: true))) == .rotateSelectionCounterclockwise)
    }

    @Test
    @MainActor
    func shortcutStoreMigratesLegacyPriorityDefaults() throws {
        let suiteName = "PhotoTriageShortcutMigration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var legacyKeys = KeyboardShortcutMap.default.keys
        legacyKeys[.priorityP0] = "q"
        legacyKeys[.priorityP1] = "w"
        legacyKeys[.priorityP2] = "e"
        legacyKeys.removeValue(forKey: .cyclicOverlay)
        let data = try JSONEncoder().encode(KeyboardShortcutMap(keys: legacyKeys))
        defaults.set(data, forKey: "PhotoTriage.KeyboardShortcutMap.v1")

        let store = KeyboardShortcutStore(defaults: defaults)

        #expect(store.map.key(for: .cyclicOverlay) == "q")
        #expect(store.map.key(for: .priorityP0) == "command+1")
        #expect(store.map.key(for: .priorityP1) == "command+2")
        #expect(store.map.key(for: .priorityP2) == "command+3")
    }

    @Test
    @MainActor
    func shortcutStoreRetiresFinderActionsWithoutLosingOtherCustomizations() throws {
        let suiteName = "PhotoTriageShortcutMigration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // The pre-migration enum-keyed dictionary was encoded as this alternating array.
        let legacy: [String: [String]] = ["keys": [
            "finderTagRed", "command+1", "finderTagClear", "command+9",
            "priorityP0", "w", "priorityP1", "e", "priorityP2", "r",
            "keep", "control+k", "nextGroup", "control+n",
        ]]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "PhotoTriage.KeyboardShortcutMap.v1")
        let store = KeyboardShortcutStore(defaults: defaults)
        #expect(store.map.key(for: .priorityP0) == "command+1")
        #expect(store.map.key(for: .priorityP1) == "command+2")
        #expect(store.map.key(for: .priorityP2) == "command+3")
        #expect(store.map.key(for: .priorityP9) == "command+0")
        #expect(store.map.key(for: .keep) == "control+k")
        #expect(store.map.key(for: .nextGroup) == "control+n")
        let roundTrip = try JSONDecoder().decode(KeyboardShortcutMap.self, from: JSONEncoder().encode(store.map))
        #expect(roundTrip == store.map)
    }

    @Test
    @MainActor
    func shortcutStorePreservesCustomPriorityBindingsDuringMigration() throws {
        let suiteName = "PhotoTriageShortcutMigration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let saved = KeyboardShortcutMap(keys: [.priorityP0: "control+p", .priorityP1: "e", .priorityP2: "r"])
        defaults.set(try JSONEncoder().encode(saved), forKey: "PhotoTriage.KeyboardShortcutMap.v1")
        let store = KeyboardShortcutStore(defaults: defaults)
        #expect(store.map.key(for: .priorityP0) == "control+p")
        #expect(store.map.key(for: .priorityP1) == "command+2")
        #expect(store.map.key(for: .priorityP2) == "command+3")
    }

    @Test @MainActor func shortcutMigrationRunsOnceAndPreservesLaterCustomWBinding() throws {
        let suiteName = "PhotoTriageShortcutMigration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = KeyboardShortcutStore(defaults: defaults)
        var custom = store.map.keys
        custom[.priorityP0] = "w"
        store.apply(custom)
        #expect(KeyboardShortcutStore(defaults: defaults).map.key(for: .priorityP0) == "w")
    }

    @Test @MainActor func newPriorityShortcutCollisionDoesNotResetUnrelatedSettings() throws {
        let suiteName = "PhotoTriageShortcutMigration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let old = KeyboardShortcutMap(keys: [.keep: "command+4", .nextGroup: "control+n"])
        defaults.set(try JSONEncoder().encode(old), forKey: "PhotoTriage.KeyboardShortcutMap.v1")
        let store = KeyboardShortcutStore(defaults: defaults)
        #expect(store.map.key(for: .priorityP3) == "command+4")
        #expect(store.map.key(for: .keep) == "a")
        #expect(store.map.key(for: .nextGroup) == "control+n")
        #expect(KeyboardShortcutMap.duplicateKeys(in: store.map.keys).isEmpty)
    }

    @Test
    func overviewPaneWidthSupportsSevenVisiblePanes() {
        let width = CompareLayoutMetrics.overviewPaneWidth(containerWidth: 1400, paneCount: 7)

        #expect(width == 200)
    }

    @Test
    func tolerancePairingAvoidsDuplicateTwoImageDifference() {
        #expect(
            CompareTolerancePairing.overviewPairs(assetCount: 2)
                == [CompareTolerancePairIndices(baseIndex: 1, overlayIndex: 0)]
        )
    }

    @Test
    func tolerancePairingMatchesCyclicOverlayForThreeOrMoreImages() {
        #expect(
            CompareTolerancePairing.overviewPairs(assetCount: 4)
                == [
                    CompareTolerancePairIndices(baseIndex: 1, overlayIndex: 0),
                    CompareTolerancePairIndices(baseIndex: 2, overlayIndex: 1),
                    CompareTolerancePairIndices(baseIndex: 3, overlayIndex: 2),
                    CompareTolerancePairIndices(baseIndex: 0, overlayIndex: 3),
                ]
        )
    }

    @Test
    func toleranceSliderMapsTheWholeControlToTheFullThresholdRange() {
        let controlWidth: CGFloat = 279
        let halfThumb = CompareToleranceSliderMetrics.thumbDiameter * 0.5

        #expect(CompareToleranceSliderMetrics.value(at: 0, controlWidth: controlWidth) == 0)
        #expect(CompareToleranceSliderMetrics.value(at: halfThumb, controlWidth: controlWidth) == 0)
        #expect(CompareToleranceSliderMetrics.value(at: controlWidth * 0.5, controlWidth: controlWidth) == 128)
        #expect(CompareToleranceSliderMetrics.value(at: controlWidth - halfThumb, controlWidth: controlWidth) == 255)
        #expect(CompareToleranceSliderMetrics.value(at: controlWidth + 100, controlWidth: controlWidth) == 255)
    }

    @Test
    func toleranceDetailPairPrefersSelectedOverlayAndFallsBackToCyclicOverlay() {
        #expect(
            CompareTolerancePairing.detailPair(assetCount: 4, focusedIndex: 1, selectedOverlayIndex: 3)
                == CompareTolerancePairIndices(baseIndex: 1, overlayIndex: 3)
        )
        #expect(
            CompareTolerancePairing.detailPair(assetCount: 4, focusedIndex: 0, selectedOverlayIndex: nil)
                == CompareTolerancePairIndices(baseIndex: 0, overlayIndex: 3)
        )
    }

    @Test
    func overlayShortcutItemSizeIsStableAcrossSelectionChanges() {
        let size = CompareLayoutMetrics.overlayShortcutItemSize()

        #expect(size.width == 176)
        #expect(size.height == 36)
    }

    @Test
    func tolerancePanelHeightStaysUsableAcrossCompareWindowSizes() {
        #expect(CompareLayoutMetrics.toleranceOverviewHeight(containerHeight: 760) == 258)
        #expect(CompareLayoutMetrics.toleranceOverviewHeight(containerHeight: 1400) == 320)
        #expect(CompareLayoutMetrics.toleranceDetailHeight() == 260)
        #expect(
            CompareLayoutMetrics.clampedToleranceHeight(
                proposedHeight: 80,
                containerHeight: 760,
                reservedUpperHeight: 280
            ) == 180
        )
        #expect(
            CompareLayoutMetrics.clampedToleranceHeight(
                proposedHeight: 900,
                containerHeight: 760,
                reservedUpperHeight: 280
            ) == 471
        )
        #expect(
            CompareLayoutMetrics.clampedToleranceHeight(
                proposedHeight: 900,
                containerHeight: 1400,
                reservedUpperHeight: 280
            ) == 520
        )
        #expect(CompareLayoutMetrics.toleranceControlWidth(containerWidth: 1180) == 240)
        #expect(CompareLayoutMetrics.toleranceControlWidth(containerWidth: 1500) == 300)
        #expect(CompareLayoutMetrics.toleranceControlWidth(containerWidth: 1800) == 320)
    }

    @Test
    func fittedImageSizeRespectsAspectRatioAndZoom() {
        let fitted = CompareLayoutMetrics.fittedImageSize(
            imageSize: CGSize(width: 6000, height: 4000),
            viewport: CGSize(width: 600, height: 500),
            zoomScale: 2
        )

        #expect(fitted.width == 1200)
        #expect(fitted.height == 800)
    }

    @Test
    func pannableContentSizeUsesFittedImageAtFitZoom() {
        let fitted = CGSize(width: 600, height: 400)
        let pannable = CompareLayoutMetrics.pannableContentSize(
            fittedContentSize: fitted,
            viewport: CGSize(width: 900, height: 700),
            zoomScale: 1
        )

        #expect(pannable.width == fitted.width)
        #expect(pannable.height == fitted.height)
    }

    @Test
    func pannableContentSizeExpandsOnlyAfterZoomingIn() {
        let pannable = CompareLayoutMetrics.pannableContentSize(
            fittedContentSize: CGSize(width: 900, height: 600),
            viewport: CGSize(width: 900, height: 700),
            zoomScale: 2
        )

        #expect(pannable.width == 1800)
        #expect(pannable.height == 1400)
    }

    @Test
    func imageDrawRectFitsWholeImageInsideContainer() {
        let rect = CompareLayoutMetrics.imageDrawRect(
            imageSize: CGSize(width: 4000, height: 3000),
            container: CGSize(width: 1000, height: 900),
            contentMode: .fit
        )

        #expect(rect.width == 1000)
        #expect(rect.height == 750)
        #expect(rect.minX == 0)
        #expect(rect.minY == 75)
    }

    @Test
    func imageDrawRectFillCanCropButStaysCentered() {
        let rect = CompareLayoutMetrics.imageDrawRect(
            imageSize: CGSize(width: 4000, height: 3000),
            container: CGSize(width: 1000, height: 900),
            contentMode: .fill
        )

        #expect(rect.width == 1200)
        #expect(rect.height == 900)
        #expect(rect.minX == -100)
        #expect(rect.minY == 0)
    }

    @Test
    func detailOverlayLocksToBaseGeometryWhenRequested() {
        let baseSize = CGSize(width: 1000, height: 750)
        let overlaySize = CGSize(width: 1000, height: 562)

        let locked = CompareLayoutMetrics.overlayContentSize(
            baseContentSize: baseSize,
            overlayContentSize: overlaySize,
            lockToBaseGeometry: true
        )
        let unlocked = CompareLayoutMetrics.overlayContentSize(
            baseContentSize: baseSize,
            overlayContentSize: overlaySize,
            lockToBaseGeometry: false
        )

        #expect(locked == baseSize)
        #expect(unlocked == overlaySize)
    }

    @Test
    func lockedOverlayDrawRectUsesWholeBaseBounds() {
        let rect = CompareLayoutMetrics.imageDrawRectLockedToBounds(container: CGSize(width: 1000, height: 750))

        #expect(rect == CGRect(x: 0, y: 0, width: 1000, height: 750))
    }

    @Test
    func normalizedPanClampsToAvailableOverflow() {
        let normalized = CompareLayoutMetrics.normalizedPan(
            start: .zero,
            translation: CGSize(width: 260, height: -400),
            viewport: CGSize(width: 400, height: 320),
            contentSize: CGSize(width: 800, height: 960)
        )

        #expect(abs(normalized.width - 1) < 0.0001)
        #expect(abs(normalized.height + 1) < 0.0001)
    }

    @Test
    func actualPanOffsetMapsSharedNormalizedPanToPaneSpecificOverflow() {
        let normalizedPan = CGSize(width: 0.5, height: -0.25)
        let actualOffset = CompareLayoutMetrics.actualPanOffset(
            normalizedPan: normalizedPan,
            viewport: CGSize(width: 400, height: 300),
            contentSize: CGSize(width: 1000, height: 700)
        )

        #expect(actualOffset.width == 150)
        #expect(actualOffset.height == -50)
    }

    @Test
    func anchoredZoomKeepsPointerContentStableWhenZoomingIn() {
        let pan = CompareLayoutMetrics.anchoredNormalizedPan(
            normalizedPan: .zero,
            from: 1,
            to: 2,
            anchor: CGPoint(x: 300, y: 150),
            containerSize: CGSize(width: 400, height: 300),
            imageSize: CGSize(width: 400, height: 300),
            viewport: CGSize(width: 400, height: 300)
        )

        #expect(abs(pan.width + 0.5) < 0.0001)
        #expect(abs(pan.height) < 0.0001)
    }

    @Test
    func anchoredZoomPreservesExistingPanAtTheViewportCenter() {
        let pan = CompareLayoutMetrics.anchoredNormalizedPan(
            normalizedPan: CGSize(width: 0.5, height: -0.5),
            from: 2,
            to: 3,
            anchor: CGPoint(x: 200, y: 150),
            containerSize: CGSize(width: 400, height: 300),
            imageSize: CGSize(width: 400, height: 300),
            viewport: CGSize(width: 400, height: 300)
        )

        #expect(abs(pan.width - 0.375) < 0.0001)
        #expect(abs(pan.height + 0.375) < 0.0001)
    }
}
