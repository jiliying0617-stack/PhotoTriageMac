import AppKit
import SwiftUI

struct KeyEventMonitor: NSViewRepresentable {
    var onKeyDown: (KeyInput) -> Bool
    var onKeyUp: (KeyInput) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown, onKeyUp: onKeyUp)
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView(frame: .zero)
        context.coordinator.hostView = view
        view.monitorCoordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
        context.coordinator.onKeyUp = onKeyUp
    }

    static func dismantleNSView(_ nsView: HostView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class HostView: NSView {
        weak var monitorCoordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                monitorCoordinator?.stop()
            } else {
                monitorCoordinator?.start()
            }
        }
    }

    @MainActor
    final class Coordinator {
        var onKeyDown: (KeyInput) -> Bool
        var onKeyUp: (KeyInput) -> Void
        weak var hostView: NSView?
        private var downMonitor: Any?
        private var upMonitor: Any?

        var isRunning: Bool {
            downMonitor != nil && upMonitor != nil
        }

        init(onKeyDown: @escaping (KeyInput) -> Bool, onKeyUp: @escaping (KeyInput) -> Void) {
            self.onKeyDown = onKeyDown
            self.onKeyUp = onKeyUp
        }

        func start() {
            guard downMonitor == nil, upMonitor == nil else { return }
            downMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleKeyDownEvent(event)
            }
            upMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                guard let self, self.shouldHandle(event) else { return event }
                guard let input = KeyInput(event: event) else { return event }
                if self.isTextInputActive(for: event), !input.isAppWideModifiedNumberShortcut {
                    return event
                }
                self.onKeyUp(input)
                return event
            }
        }

        func handleKeyDownEvent(_ event: NSEvent) -> NSEvent? {
            // Each key event is authoritative. Per-window flagsChanged caches miss
            // releases in other windows/apps and can turn Cmd+2 into Shift+Cmd+2.
            guard shouldHandle(event), let input = KeyInput(event: event) else { return event }
            if isTextInputActive(for: event), !input.isAppWideModifiedNumberShortcut { return event }
            return onKeyDown(input) ? nil : event
        }

        func stop() {
            if let downMonitor {
                NSEvent.removeMonitor(downMonitor)
                self.downMonitor = nil
            }
            if let upMonitor {
                NSEvent.removeMonitor(upMonitor)
                self.upMonitor = nil
            }
        }

        private func isTextInputActive(for event: NSEvent) -> Bool {
            // Use the same resolved window as routing when AppKit omits it.
            (event.window ?? hostView?.window)?.firstResponder is NSTextView
        }

        private func shouldHandle(_ event: NSEvent) -> Bool {
            guard let hostWindow = hostView?.window,
                  hostWindow.attachedSheet == nil else { return false }
            return KeyEventWindowRouting.shouldHandle(
                eventWindowNumber: event.window?.windowNumber,
                hostWindowNumber: hostWindow.windowNumber,
                isHostKeyWindow: hostWindow.isKeyWindow
            )
        }
    }
}

enum KeyEventWindowRouting {
    static func shouldHandle(
        eventWindowNumber: Int?,
        hostWindowNumber: Int?,
        isHostKeyWindow: Bool
    ) -> Bool {
        guard let hostWindowNumber else { return false }
        // An explicit event window must never be claimed by a different key window.
        if let eventWindowNumber { return eventWindowNumber == hostWindowNumber }
        return isHostKeyWindow
    }
}

public struct KeyInput: Equatable {
    public let characters: String
    public let keyCode: UInt16?
    public let isShiftPressed: Bool
    public let isOptionPressed: Bool
    public let isCommandPressed: Bool
    public let isControlPressed: Bool
    public let isRepeat: Bool

    public init?(
        characters: String,
        keyCode: UInt16? = nil,
        isShiftPressed: Bool = false,
        isOptionPressed: Bool = false,
        isCommandPressed: Bool = false,
        isControlPressed: Bool = false,
        isRepeat: Bool = false
    ) {
        // Input methods and non-US layouts can send no characters at all.
        // A known hardware key is sufficient; never require translated text.
        guard !characters.isEmpty || keyCode.flatMap(PhysicalShortcutKey.name) != nil else { return nil }
        self.characters = characters
        self.keyCode = keyCode
        self.isShiftPressed = isShiftPressed
        self.isOptionPressed = isOptionPressed
        self.isCommandPressed = isCommandPressed
        self.isControlPressed = isControlPressed
        self.isRepeat = isRepeat
    }

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags
        self.init(
            characters: event.charactersIgnoringModifiers ?? "",
            keyCode: event.keyCode,
            isShiftPressed: modifiers.contains(.shift),
            isOptionPressed: modifiers.contains(.option),
            isCommandPressed: modifiers.contains(.command),
            isControlPressed: modifiers.contains(.control),
            isRepeat: event.isARepeat
        )
    }

    public var numberKey: Int? {
        if let keyCode {
            // Do not mistake a translated digit on a different physical key for a number key.
            return PhysicalShortcutKey.name(for: keyCode).flatMap(Int.init)
        }

        if characters.count == 1, let number = Int(characters), (0...9).contains(number) {
            return number
        }

        // AppKit keeps Shift when producing charactersIgnoringModifiers, so
        // Shift+1 may arrive as "!" even though it is the physical 1 key.
        return switch characters {
        case "!": 1
        case "@": 2
        case "#": 3
        case "$": 4
        case "%": 5
        case "^": 6
        case "&": 7
        case "*": 8
        case "(": 9
        case ")": 0
        default: nil
        }
    }

    public var isAppWideModifiedNumberShortcut: Bool {
        guard numberKey != nil else { return false }
        let isCommandOnly = isCommandPressed && !isShiftPressed && !isOptionPressed && !isControlPressed
        let isShiftOnly = isShiftPressed && !isCommandPressed && !isOptionPressed && !isControlPressed
        return isCommandOnly || isShiftOnly
    }

}

/// One physical-key vocabulary shared by shortcut recording and execution.
enum PhysicalShortcutKey {
    static func name(for keyCode: UInt16) -> String? { names[keyCode] }

    private static let names: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
        31: "o", 32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
        36: "return", 48: "tab", 49: "space", 51: "delete", 53: "escape",
        65: ".", 67: "*", 69: "+", 75: "/", 76: "return", 78: "-", 81: "=",
        82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
        123: "arrowleft", 124: "arrowright", 125: "arrowdown", 126: "arrowup",
    ]
}
