import SwiftUI
import PhotoTriageCore
#if canImport(AppKit)
import AppKit
#endif

public struct AppSettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            PriorityTagEditorView()
                .tabItem { Label("P 标签", systemImage: "tag") }

            InteractionSettingsView()
                .tabItem {
                    Label("滚动与缩放", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                }

            ShortcutSettingsView()
                .tabItem {
                    Label("快捷键", systemImage: "keyboard")
                }
        }
        .frame(width: 680, height: 680)
    }
}

public struct InteractionSettingsView: View {
    @EnvironmentObject private var interactions: InteractionSettingsStore

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle(isOn: $interactions.wheelZoomEnabled) {
                    SettingsRowLabel(
                        title: "滚轮缩放",
                        subtitle: "鼠标停在哪张图上，就缩放该位置",
                        systemImage: "plus.magnifyingglass"
                    )
                }

                Toggle(isOn: $interactions.naturalScrollZoom) {
                    SettingsRowLabel(
                        title: "自然滚动方向",
                        subtitle: "开启后跟随触控板手势；关闭后方向相反",
                        systemImage: "arrow.up.arrow.down"
                    )
                }
                .disabled(!interactions.wheelZoomEnabled)
            } header: {
                Text("滚动与缩放")
            } footer: {
                Text("缩放会同步作用于原图和容差图，并始终以鼠标所在位置为中心。")
            }

            Section {
                HStack {
                    Spacer()
                    Button("恢复默认") {
                        interactions.resetToDefaults()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

public struct ShortcutSettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var shortcuts: KeyboardShortcutStore
    @State private var draft: [KeyboardShortcutAction: String] = KeyboardShortcutMap.default.keys
    @State private var recordingAction: KeyboardShortcutAction?

    private let groupOrder = [
        "筛选", "P 标签", "主界面浏览",
        "对比导航", "叠图选择", "图片旋转",
    ]

    public init() {}

    public var body: some View {
        Form {
            Section {
                Text("点击右侧按键框，再按下新的快捷键。按物理键位识别，不受输入法影响；按住 Command 可连续按数字给整组图片切换 P 标签；大图对比中先把鼠标移到目标图片上，再按 Option + Command + 数字，只给悬停图片打 P 标签。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(groupOrder, id: \.self) { group in
                Section(group) {
                    shortcutRows(for: KeyboardShortcutAction.allCases.filter {
                        $0.groupTitle == group
                            && ($0.priorityTag.map { state.priorityTags.contains($0) } ?? true)
                    })
                }
            }

            Section {
                HStack(spacing: 12) {
                    Button("恢复默认") {
                        recordingAction = nil
                        draft = KeyboardShortcutMap.default.keys
                        shortcuts.resetToDefaults()
                    }

                    Spacer()

                    if hasUnsavedChanges {
                        Text("有未保存的更改")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("保存") {
                        recordingAction = nil
                        shortcuts.apply(draft)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || !hasUnsavedChanges)
                }

                if !duplicateDisplayText.isEmpty {
                    Label("快捷键冲突：\(duplicateDisplayText)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if !reservedKeys.isEmpty {
                    Label("系统保留快捷键：\(reservedKeys.map(KeyboardShortcutMap.displayText(for:)).sorted().joined(separator: "、"))，请选择其他组合。", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .background {
#if canImport(AppKit)
            ShortcutEventCapture(
                isActive: recordingAction != nil,
                onCapture: record
            )
            .frame(width: 0, height: 0)
#endif
        }
        .onAppear {
            draft = shortcuts.map.keys
        }
        .onDisappear {
            recordingAction = nil
        }
    }

    @ViewBuilder
    private func shortcutRows(for actions: [KeyboardShortcutAction]) -> some View {
        ForEach(actions) { action in
            ShortcutEditRow(
                title: action.priorityTag.map { "\($0.rawValue) · \(state.priorityTagDisplayName($0))" } ?? action.title,
                shortcutText: KeyboardShortcutMap.displayText(for: draft[action] ?? action.defaultKey),
                isRecording: recordingAction == action,
                hasConflict: duplicateKeys.union(reservedKeys).contains(KeyboardShortcutMap.normalizedKey(draft[action] ?? "")),
                onRecord: {
                    recordingAction = recordingAction == action ? nil : action
                }
            )
        }
    }

    private var canSave: Bool {
        !draft.values.contains { KeyboardShortcutMap.normalizedKey($0).isEmpty }
            && duplicateKeys.isEmpty
            && reservedKeys.isEmpty
    }

    private var hasUnsavedChanges: Bool {
        KeyboardShortcutAction.allCases.contains { action in
            KeyboardShortcutMap.normalizedKey(draft[action] ?? action.defaultKey)
                != shortcuts.map.key(for: action)
        }
    }

    private var duplicateKeys: Set<String> {
        KeyboardShortcutMap.duplicateKeys(in: draft)
    }

    private var reservedKeys: Set<String> {
        KeyboardShortcutMap.reservedKeys(in: draft)
    }

    private var duplicateDisplayText: String {
        duplicateKeys
            .map(KeyboardShortcutMap.displayText(for:))
            .sorted()
            .joined(separator: "、")
    }

    private func record(_ input: KeyInput) {
        guard let action = recordingAction else { return }
        let key = KeyboardShortcutMap.canonicalKey(for: input)
        guard !key.isEmpty else { return }
        draft[action] = key
        recordingAction = nil
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ShortcutEditRow: View {
    let title: String
    let shortcutText: String
    let isRecording: Bool
    let hasConflict: Bool
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRecord) {
                HStack(spacing: 7) {
                    if isRecording {
                        Image(systemName: "keyboard.badge.ellipsis")
                        Text("请按键…")
                    } else {
                        Text(shortcutText)
                    }
                }
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(hasConflict ? Color.red : Color.primary)
                .frame(minWidth: 104)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    isRecording ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            hasConflict ? Color.red.opacity(0.8) : (isRecording ? Color.accentColor : Color.secondary.opacity(0.25)),
                            lineWidth: isRecording ? 1.5 : 1
                        )
                }
            }
            .buttonStyle(.plain)
            .help(isRecording ? "再次点击可取消录入" : "点击后录入新快捷键")

            if hasConflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help("此快捷键与同一界面的其他操作冲突")
            }
        }
        .padding(.vertical, 2)
    }
}

#if canImport(AppKit)
private struct ShortcutEventCapture: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (KeyInput) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView(frame: .zero)
        view.coordinator = context.coordinator
        context.coordinator.hostView = view
        return view
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        context.coordinator.onCapture = onCapture
        context.coordinator.setActive(isActive)
    }

    static func dismantleNSView(_ nsView: HostView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class HostView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.refreshMonitor()
        }
    }

    @MainActor
    final class Coordinator {
        var onCapture: (KeyInput) -> Void
        weak var hostView: NSView?
        private var monitor: Any?
        private var isActive = false

        init(onCapture: @escaping (KeyInput) -> Void) {
            self.onCapture = onCapture
        }

        func setActive(_ value: Bool) {
            isActive = value
            refreshMonitor()
        }

        func refreshMonitor() {
            guard isActive, hostView?.window != nil else {
                stop()
                return
            }
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.isActive,
                      let hostWindow = self.hostView?.window,
                      event.window?.windowNumber == hostWindow.windowNumber,
                      let input = KeyInput(event: event) else {
                    return event
                }

                self.isActive = false
                self.stop()
                self.onCapture(input)
                return nil
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
#endif
