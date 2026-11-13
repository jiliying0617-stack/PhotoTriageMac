import PhotoTriageCore
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

public enum CompareWindowScene {
    public static let windowID = "compare-window"
}

public struct CompareWindowView: View {
    @EnvironmentObject private var state: AppState

    public init() {}

    public var body: some View {
        CompareCanvasView()
            .background(Color(nsColor: .windowBackgroundColor))
            .frame(
                minWidth: CompareLayoutMetrics.compareWindowMinimumSize().width,
                minHeight: CompareLayoutMetrics.compareWindowMinimumSize().height
            )
            .background {
                CompareWindowLifecycleObserver {
                    if state.mode == .compare {
                        state.exitCompareMode()
                    }
                }
            }
            .navigationTitle(state.isSingleImageCompareMode ? "查看" : "对比")
    }
}

#if canImport(AppKit)
struct CompareWindowLifecycleObserver: NSViewRepresentable {
    let onWindowWillClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWindowWillClose: onWindowWillClose)
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView(frame: .zero)
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        context.coordinator.onWindowWillClose = onWindowWillClose
    }

    static func dismantleNSView(_ nsView: HostView, coordinator: Coordinator) {
        coordinator.detach()
        nsView.coordinator = nil
    }

    @MainActor
    final class HostView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { coordinator?.attach(to: window) }
            else { coordinator?.detach() }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onWindowWillClose: () -> Void
        weak var window: NSWindow?

        init(onWindowWillClose: @escaping () -> Void) {
            self.onWindowWillClose = onWindowWillClose
        }

        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            detach()
            self.window = window
            // SwiftUI owns the window delegate. Replacing it drops lifecycle and
            // restoration methods we never forwarded and leaves deferred attaches
            // racing dismantle. Observe only the event this view actually needs.
            NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: window)
        }

        func detach() {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
            self.window = nil
        }

        @objc func windowWillClose(_ notification: Notification) {
            onWindowWillClose()
        }
    }
}
#else
private struct CompareWindowLifecycleObserver: View {
    let onWindowWillClose: () -> Void

    var body: some View {
        Color.clear
    }
}
#endif
