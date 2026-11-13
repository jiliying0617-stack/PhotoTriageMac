import Combine
import Foundation
import PhotoTriageCore
import SwiftUI

public struct KeyboardShortcutScope: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let workspace = KeyboardShortcutScope(rawValue: 1 << 0)
    public static let compare = KeyboardShortcutScope(rawValue: 1 << 1)
    public static let all: KeyboardShortcutScope = [.workspace, .compare]
}

public enum KeyboardShortcutAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case keep
    case pending
    case reject
    case clearAllTags
    case priorityP0
    case priorityP1
    case priorityP2
    case priorityP3
    case priorityP4
    case priorityP5
    case priorityP6
    case priorityP7
    case priorityP8
    case priorityP9

    case enterCompare
    case openFocusedItem
    case previousItemLeft
    case previousItemUp
    case nextItemRight
    case nextItemDown

    case cyclicOverlay
    case toleranceView
    case previousGroup
    case previousGroupArrow
    case nextGroup
    case nextGroupArrow
    case showOverview
    case overlay1
    case overlay2
    case overlay3
    case overlay4
    case overlay5
    case overlay6
    case overlay7
    case overlay8
    case overlay9

    case rotatePane1
    case rotatePane2
    case rotatePane3
    case rotatePane4
    case rotatePane5
    case rotatePane6
    case rotatePane7
    case rotatePane8
    case rotatePane9
    case rotateFocusedCounterclockwise
    case rotateSelectionClockwise
    case rotateSelectionCounterclockwise

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keep: "保留"
        case .pending: "恢复"
        case .reject: "淘汰"
        case .clearAllTags: "清除选中标签"
        case .priorityP0: "P0"
        case .priorityP1: "P1"
        case .priorityP2: "P2"
        case .priorityP3: "P3"
        case .priorityP4: "P4"
        case .priorityP5: "P5"
        case .priorityP6: "P6"
        case .priorityP7: "P7"
        case .priorityP8: "P8"
        case .priorityP9: "P9"
        case .enterCompare: "多选后进入对比"
        case .openFocusedItem: "打开当前图片"
        case .previousItemLeft: "选择上一张（横向）"
        case .previousItemUp: "选择上一张（纵向）"
        case .nextItemRight: "选择下一张（横向）"
        case .nextItemDown: "选择下一张（纵向）"
        case .cyclicOverlay: "按住循环叠图"
        case .toleranceView: "显示 / 隐藏容差"
        case .previousGroup: "上一组"
        case .previousGroupArrow: "上一组（方向键）"
        case .nextGroup: "下一组"
        case .nextGroupArrow: "下一组（方向键）"
        case .showOverview: "返回对比总览"
        case .overlay1: "选择叠图 1"
        case .overlay2: "选择叠图 2"
        case .overlay3: "选择叠图 3"
        case .overlay4: "选择叠图 4"
        case .overlay5: "选择叠图 5"
        case .overlay6: "选择叠图 6"
        case .overlay7: "选择叠图 7"
        case .overlay8: "选择叠图 8"
        case .overlay9: "选择叠图 9"
        case .rotatePane1: "旋转第 1 张"
        case .rotatePane2: "旋转第 2 张"
        case .rotatePane3: "旋转第 3 张"
        case .rotatePane4: "旋转第 4 张"
        case .rotatePane5: "旋转第 5 张"
        case .rotatePane6: "旋转第 6 张"
        case .rotatePane7: "旋转第 7 张"
        case .rotatePane8: "旋转第 8 张"
        case .rotatePane9: "旋转第 9 张"
        case .rotateFocusedCounterclockwise: "当前图片逆时针旋转"
        case .rotateSelectionClockwise: "整组顺时针旋转"
        case .rotateSelectionCounterclockwise: "整组逆时针旋转"
        }
    }

    public var groupTitle: String {
        switch self {
        case .keep, .pending, .reject, .clearAllTags:
            "筛选"
        case .priorityP0, .priorityP1, .priorityP2, .priorityP3, .priorityP4,
             .priorityP5, .priorityP6, .priorityP7, .priorityP8, .priorityP9:
            "P 标签"
        case .enterCompare, .openFocusedItem, .previousItemLeft, .previousItemUp, .nextItemRight, .nextItemDown:
            "主界面浏览"
        case .cyclicOverlay, .toleranceView, .previousGroup, .previousGroupArrow,
             .nextGroup, .nextGroupArrow, .showOverview:
            "对比导航"
        case .overlay1, .overlay2, .overlay3, .overlay4, .overlay5, .overlay6, .overlay7, .overlay8, .overlay9:
            "叠图选择"
        case .rotatePane1, .rotatePane2, .rotatePane3, .rotatePane4, .rotatePane5,
             .rotatePane6, .rotatePane7, .rotatePane8, .rotatePane9,
             .rotateFocusedCounterclockwise, .rotateSelectionClockwise, .rotateSelectionCounterclockwise:
            "图片旋转"
        }
    }

    public var scope: KeyboardShortcutScope {
        switch self {
        case .enterCompare, .openFocusedItem, .previousItemLeft, .previousItemUp, .nextItemRight, .nextItemDown:
            .workspace
        case .cyclicOverlay, .toleranceView, .previousGroup, .previousGroupArrow,
             .nextGroup, .nextGroupArrow, .showOverview,
             .overlay1, .overlay2, .overlay3, .overlay4, .overlay5, .overlay6, .overlay7, .overlay8, .overlay9,
             .rotatePane1, .rotatePane2, .rotatePane3, .rotatePane4, .rotatePane5,
             .rotatePane6, .rotatePane7, .rotatePane8, .rotatePane9,
             .rotateFocusedCounterclockwise, .rotateSelectionClockwise, .rotateSelectionCounterclockwise:
            .compare
        default:
            .all
        }
    }

    public var defaultKey: String {
        switch self {
        case .keep: "a"
        case .pending: "s"
        case .reject: "d"
        case .clearAllTags: "x"
        case .priorityP0: "command+1"
        case .priorityP1: "command+2"
        case .priorityP2: "command+3"
        case .priorityP3: "command+4"
        case .priorityP4: "command+5"
        case .priorityP5: "command+6"
        case .priorityP6: "command+7"
        case .priorityP7: "command+8"
        case .priorityP8: "command+9"
        case .priorityP9: "command+0"
        case .enterCompare: "space"
        case .openFocusedItem: "return"
        case .previousItemLeft: "arrowleft"
        case .previousItemUp: "arrowup"
        case .nextItemRight: "arrowright"
        case .nextItemDown: "arrowdown"
        case .cyclicOverlay: "q"
        case .toleranceView: "0"
        case .previousGroup: "b"
        case .previousGroupArrow: "arrowup"
        case .nextGroup: "space"
        case .nextGroupArrow: "arrowdown"
        case .showOverview: "escape"
        case .overlay1: "1"
        case .overlay2: "2"
        case .overlay3: "3"
        case .overlay4: "4"
        case .overlay5: "5"
        case .overlay6: "6"
        case .overlay7: "7"
        case .overlay8: "8"
        case .overlay9: "9"
        case .rotatePane1: "shift+1"
        case .rotatePane2: "shift+2"
        case .rotatePane3: "shift+3"
        case .rotatePane4: "shift+4"
        case .rotatePane5: "shift+5"
        case .rotatePane6: "shift+6"
        case .rotatePane7: "shift+7"
        case .rotatePane8: "shift+8"
        case .rotatePane9: "shift+9"
        case .rotateFocusedCounterclockwise: "shift+r"
        case .rotateSelectionClockwise: "option+r"
        case .rotateSelectionCounterclockwise: "option+shift+r"
        }
    }

    public var priorityTag: PriorityTag? {
        switch self {
        case .priorityP0: .p0
        case .priorityP1: .p1
        case .priorityP2: .p2
        case .priorityP3: PriorityTag(index: 3)
        case .priorityP4: PriorityTag(index: 4)
        case .priorityP5: PriorityTag(index: 5)
        case .priorityP6: PriorityTag(index: 6)
        case .priorityP7: PriorityTag(index: 7)
        case .priorityP8: PriorityTag(index: 8)
        case .priorityP9: PriorityTag(index: 9)
        default: nil
        }
    }

    public static func priorityAction(for tag: PriorityTag) -> KeyboardShortcutAction? {
        KeyboardShortcutAction(rawValue: "priorityP\(tag.index)")
    }

    public var overlaySlot: Int? {
        switch self {
        case .overlay1: 1
        case .overlay2: 2
        case .overlay3: 3
        case .overlay4: 4
        case .overlay5: 5
        case .overlay6: 6
        case .overlay7: 7
        case .overlay8: 8
        case .overlay9: 9
        default: nil
        }
    }

    public var rotatePaneSlot: Int? {
        switch self {
        case .rotatePane1: 1
        case .rotatePane2: 2
        case .rotatePane3: 3
        case .rotatePane4: 4
        case .rotatePane5: 5
        case .rotatePane6: 6
        case .rotatePane7: 7
        case .rotatePane8: 8
        case .rotatePane9: 9
        default: nil
        }
    }

    public var isCyclicOverlay: Bool {
        self == .cyclicOverlay
    }

    public var isToleranceView: Bool {
        self == .toleranceView
    }

    public var isPreviousGroup: Bool {
        self == .previousGroup
    }
}

public struct KeyboardShortcutMap: Equatable, Codable, Sendable {
    public var keys: [KeyboardShortcutAction: String]

    public init() {
        keys = KeyboardShortcutAction.defaultKeys
    }

    public init(keys: [KeyboardShortcutAction: String]) {
        self.keys = keys
    }

    private enum CodingKeys: String, CodingKey { case keys }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Older versions encoded enum-keyed dictionaries as alternating key/value
        // arrays. Ignore retired actions without discarding unrelated user shortcuts.
        if let dictionary = try? container.decode([String: String].self, forKey: .keys) {
            keys = Dictionary(uniqueKeysWithValues: dictionary.compactMap { name, key in
                KeyboardShortcutAction(rawValue: name).map { ($0, key) }
            })
        } else {
            var legacy = try container.nestedUnkeyedContainer(forKey: .keys)
            var decoded: [KeyboardShortcutAction: String] = [:]
            while !legacy.isAtEnd {
                let name = try legacy.decode(String.self)
                let key = try legacy.decode(String.self)
                if let action = KeyboardShortcutAction(rawValue: name) {
                    decoded[action] = key
                }
            }
            keys = decoded
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let dictionary = Dictionary(uniqueKeysWithValues: keys.map { ($0.key.rawValue, $0.value) })
        try container.encode(dictionary, forKey: .keys)
    }

    public static let `default` = KeyboardShortcutMap()

    public func key(for action: KeyboardShortcutAction) -> String {
        keys[action] ?? action.defaultKey
    }

    public func displayKey(for action: KeyboardShortcutAction) -> String {
        Self.displayText(for: key(for: action))
    }

    public func action(
        for input: KeyInput,
        scope: KeyboardShortcutScope = .all
    ) -> KeyboardShortcutAction? {
        let chord = Self.canonicalKey(for: input)
        guard !chord.isEmpty else { return nil }
        return KeyboardShortcutAction.allCases.first {
            !$0.scope.intersection(scope).isEmpty && key(for: $0) == chord
        }
    }

    public func overlaySlot(for input: KeyInput) -> Int? {
        action(for: input)?.overlaySlot
    }

    public func priorityTag(for input: KeyInput) -> PriorityTag? {
        action(for: input)?.priorityTag
    }

    public static func canonicalKey(for input: KeyInput) -> String {
        let base: String
        if let keyCode = input.keyCode {
            base = PhysicalShortcutKey.name(for: keyCode) ?? ""
        } else {
            base = normalizedBaseKey(input.characters)
        }
        guard !base.isEmpty else { return "" }

        var components: [String] = []
        if input.isControlPressed { components.append("control") }
        if input.isOptionPressed { components.append("option") }
        if input.isShiftPressed { components.append("shift") }
        if input.isCommandPressed { components.append("command") }
        components.append(base)
        return components.joined(separator: "+")
    }

    public static func normalizedKey(_ value: String) -> String {
        if value == " " { return "space" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }

        // The keypad + key is a base key, not a trailing separator.
        let escapedPlus = trimmed == "+" ? "plus" : (trimmed.hasSuffix("++") ? String(trimmed.dropLast()) + "plus" : trimmed)
        let parts = escapedPlus.split(separator: "+", omittingEmptySubsequences: true).map(String.init)
        guard let rawBase = parts.last else { return "" }
        let base = normalizedBaseKey(rawBase)
        guard !base.isEmpty else { return "" }

        let modifierParts = Set(parts.dropLast().compactMap(normalizedModifier))
        var components: [String] = []
        for modifier in ["control", "option", "shift", "command"] where modifierParts.contains(modifier) {
            components.append(modifier)
        }
        components.append(base)
        return components.joined(separator: "+")
    }

    public static func displayText(for key: String) -> String {
        let normalized = normalizedKey(key)
        guard !normalized.isEmpty else { return "未设置" }
        let displayParts = normalized == "+" ? "plus" : (normalized.hasSuffix("++") ? String(normalized.dropLast()) + "plus" : normalized)
        let parts = displayParts.split(separator: "+").map(String.init)
        guard let base = parts.last else { return "未设置" }

        let modifiers = parts.dropLast().map { part in
            switch part {
            case "control": "⌃"
            case "option": "⌥"
            case "shift": "⇧"
            case "command": "⌘"
            default: ""
            }
        }.joined()

        let baseDisplay = switch base {
        case "plus": "+"
        case "space": "Space"
        case "return": "Return"
        case "escape": "Esc"
        case "tab": "Tab"
        case "delete": "Delete"
        case "arrowleft": "←"
        case "arrowright": "→"
        case "arrowup": "↑"
        case "arrowdown": "↓"
        default: base.uppercased()
        }
        return modifiers + baseDisplay
    }

    public static func duplicateKeys(in keys: [KeyboardShortcutAction: String]) -> Set<String> {
        var owners: [String: [KeyboardShortcutAction]] = [:]
        var duplicates: Set<String> = []

        for action in KeyboardShortcutAction.allCases {
            let key = normalizedKey(keys[action] ?? action.defaultKey)
            guard !key.isEmpty else { continue }
            let overlappingOwner = owners[key, default: []].contains { !$0.scope.intersection(action.scope).isEmpty }
            if overlappingOwner {
                duplicates.insert(key)
            }
            owners[key, default: []].append(action)
        }
        return duplicates
    }

    private static func normalizedModifier(_ value: String) -> String? {
        switch value {
        case "control", "ctrl", "⌃": "control"
        case "option", "alt", "⌥": "option"
        case "shift", "⇧": "shift"
        case "command", "cmd", "⌘": "command"
        default: nil
        }
    }

    private static func normalizedBaseKey(_ value: String) -> String {
        return switch value.lowercased() {
        case "+", "plus": "+"
        case " ", "space", "空格": "space"
        case "\r", "\n", "return", "enter", "回车": "return"
        case "\u{1b}", "escape", "esc": "escape"
        case "\t", "tab": "tab"
        case "\u{7f}", "delete", "backspace": "delete"
        case "\u{f702}", "arrowleft", "left", "←": "arrowleft"
        case "\u{f703}", "arrowright", "right", "→": "arrowright"
        case "\u{f700}", "arrowup", "up", "↑": "arrowup"
        case "\u{f701}", "arrowdown", "down", "↓": "arrowdown"
        default:
            value.first.map { String($0).lowercased() } ?? ""
        }
    }

    /// Keep native editing, window management and application commands available.
    public static func reservedKeys(in keys: [KeyboardShortcutAction: String]) -> Set<String> {
        Set(keys.values.map(normalizedKey)).intersection(reservedChords)
    }

    private static let reservedChords: Set<String> = [
        "command+q", "command+w", "command+m", "command+h", "command+,",
        "option+command+w", "option+command+h", "command+tab", "shift+command+tab",
        "command+space", "control+command+q", "option+command+escape",
        "command+a", "command+c", "command+x", "command+v", "command+z", "shift+command+z",
    ]

}

private extension KeyboardShortcutAction {
    static var defaultKeys: [KeyboardShortcutAction: String] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.defaultKey) })
    }
}

@MainActor
public final class KeyboardShortcutStore: ObservableObject {
    private static let defaultsKey = "PhotoTriage.KeyboardShortcutMap.v2"
    private static let legacyDefaultsKey = "PhotoTriage.KeyboardShortcutMap.v1"

    @Published public private(set) var map: KeyboardShortcutMap

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        map = Self.loadMap(from: defaults)
        save()
    }

    public func action(
        for input: KeyInput,
        scope: KeyboardShortcutScope = .all
    ) -> KeyboardShortcutAction? {
        map.action(for: input, scope: scope)
    }

    public func apply(_ draft: [KeyboardShortcutAction: String]) {
        let normalized = Dictionary(uniqueKeysWithValues: KeyboardShortcutAction.allCases.map { action in
            (action, KeyboardShortcutMap.normalizedKey(draft[action] ?? action.defaultKey))
        })
        guard !normalized.values.contains(where: \.isEmpty),
              KeyboardShortcutMap.duplicateKeys(in: normalized).isEmpty,
              KeyboardShortcutMap.reservedKeys(in: normalized).isEmpty else {
            return
        }
        map = KeyboardShortcutMap(keys: normalized)
        save()
    }

    public func resetToDefaults() {
        map = .default
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func loadMap(from defaults: UserDefaults) -> KeyboardShortcutMap {
        let isLegacy = defaults.data(forKey: defaultsKey) == nil
        guard let data = defaults.data(forKey: defaultsKey) ?? defaults.data(forKey: legacyDefaultsKey),
              let decoded = try? JSONDecoder().decode(KeyboardShortcutMap.self, from: data) else {
            return .default
        }

        let merged = Dictionary(uniqueKeysWithValues: KeyboardShortcutAction.allCases.map { action in
            (action, KeyboardShortcutMap.normalizedKey(decoded.keys[action] ?? action.defaultKey))
        })
        var migrated = isLegacy ? migrateLegacyPriorityShortcuts(merged) : merged
        let reserved = KeyboardShortcutMap.reservedKeys(in: migrated)
        for action in KeyboardShortcutAction.allCases where reserved.contains(migrated[action] ?? "") {
            migrated[action] = action.defaultKey
        }
        // New P slots may collide with a formerly customized unrelated action.
        // Reset only conflicted owners, preserving every unrelated customization.
        for _ in KeyboardShortcutAction.allCases {
            let conflicts = KeyboardShortcutMap.duplicateKeys(in: migrated)
            guard !conflicts.isEmpty else { break }
            for action in KeyboardShortcutAction.allCases where conflicts.contains(migrated[action] ?? action.defaultKey) {
                migrated[action] = action.defaultKey
            }
        }
        guard KeyboardShortcutMap.duplicateKeys(in: migrated).isEmpty,
              !migrated.values.contains(where: \.isEmpty) else { return .default }
        return KeyboardShortcutMap(keys: migrated)
    }

    private static func migrateLegacyPriorityShortcuts(
        _ keys: [KeyboardShortcutAction: String]
    ) -> [KeyboardShortcutAction: String] {
        var migrated = keys
        let oldestDefaults = keys[.priorityP0] == "q"
            && keys[.priorityP1] == "w"
            && keys[.priorityP2] == "e"
        if oldestDefaults {
            migrated[.cyclicOverlay] = KeyboardShortcutAction.cyclicOverlay.defaultKey
        }
        let legacyDefaults: [KeyboardShortcutAction: String] = [
            .priorityP0: "w", .priorityP1: "e", .priorityP2: "r",
        ]
        for (action, oldKey) in legacyDefaults where oldestDefaults || keys[action] == oldKey {
            migrated[action] = action.defaultKey
        }
        return migrated
    }
}
