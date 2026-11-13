import PhotoTriageCore
import SwiftUI
import AppKit

/// Drafts are committed explicitly so entering text never changes the active filter.
struct PriorityTagEditorView: View {
    @EnvironmentObject private var state: AppState
    @State private var errorMessage: String?
    var addingTag = false
    @State private var prepared = false
    @FocusState private var focusedTag: PriorityTag?
    @State private var newlyAddedTag: PriorityTag?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("编辑 P 标签").font(.title2.weight(.semibold))
                Spacer()
                Button {
                    addTag()
                } label: {
                    Label("新增标签", systemImage: "plus")
                }
            }
            Text("名称用于筛选、打标和导出分类文件夹。图片文件名保持不变。")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(state.priorityTagDefinitions) { definition in
                            PriorityTagNameRow(definition: definition, focusedTag: $focusedTag) { name in
                                try state.renamePriorityTag(definition.tag, to: name)
                            }
                            .id(definition.tag)
                        }
                    }
                }
                .onChange(of: newlyAddedTag) { _, tag in
                    guard let tag else { return }
                    proxy.scrollTo(tag, anchor: .center)
                    focusedTag = tag
                }
            }
            if let message = errorMessage ?? state.priorityTagCatalogErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("⌘1–⌘9 对应 P0–P8，⌘0 对应 P9；更多标签可在右键菜单选择。改名不改变编号。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 320, idealHeight: 420)
        .task {
            guard !prepared else { return }
            prepared = true
            if addingTag { addTag() }
        }
    }

    private func addTag() {
        do { newlyAddedTag = try state.addPriorityTag(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct PriorityTagNameRow: View {
    let definition: PriorityTagDefinition
    let save: (String) throws -> Void
    var focusedTag: FocusState<PriorityTag?>.Binding
    @State private var draft: String
    @State private var errorMessage: String?

    init(definition: PriorityTagDefinition, focusedTag: FocusState<PriorityTag?>.Binding, save: @escaping (String) throws -> Void) {
        self.definition = definition
        self.save = save
        self.focusedTag = focusedTag
        _draft = State(initialValue: definition.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Circle().fill(TagPill.tintColor(for: definition.tag)).frame(width: 9, height: 9)
                Text(definition.tag.rawValue).font(.callout.monospacedDigit())
                    .frame(width: 42, alignment: .leading)
                TextField("标签名称", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused(focusedTag, equals: definition.tag)
                    .accessibilityLabel("\(definition.tag.rawValue) 标签名称")
                    .onSubmit(commit)
                Button("保存", action: commit).disabled(draft == definition.name)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: definition.name) { _, name in draft = name }
    }

    private func commit() {
        do { try save(draft); draft = draft.trimmingCharacters(in: .whitespacesAndNewlines); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

/// Attach management to the actual comparison window, not the hidden workspace.
@MainActor
enum PriorityTagEditorPresenter {
    static func present(state: AppState, in parent: NSWindow?, addingTag: Bool = false) {
        guard let parent, parent.attachedSheet == nil else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = addingTag ? "新增 P 标签" : "编辑 P 标签名称"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView:
            VStack(spacing: 0) {
                PriorityTagEditorView(addingTag: addingTag).environmentObject(state)
                HStack {
                    Spacer()
                    Button("完成") { [weak parent, weak panel] in
                        guard let parent, let panel else { return }
                        parent.endSheet(panel)
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding([.horizontal, .bottom], 20)
            }.frame(width: 560, height: 480)
        )
        parent.beginSheet(panel) { _ in panel.orderOut(nil) }
    }
}

struct PriorityTagContextMenu: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var shortcuts: KeyboardShortcutStore
    let onApply: (PriorityTag) -> Void

    var body: some View {
        ForEach(state.priorityTags) { tag in
            Button(title(for: tag)) { onApply(tag) }
        }
    }

    private func title(for tag: PriorityTag) -> String {
        let name = state.priorityTagDisplayName(tag)
        guard let action = KeyboardShortcutAction.allCases.first(where: { $0.priorityTag == tag }) else { return name }
        return "\(name)（\(KeyboardShortcutMap.displayText(for: shortcuts.map.keys[action] ?? action.defaultKey))）"
    }
}
