#if os(macOS)
import SwiftUI
import AppKit

// Reports the hosting window's width, and again whenever it is resized.
//
// WINDOW width, deliberately — not the content column's. A rule keyed off content width oscillates
// once it can hide a side panel: hiding widens the content, which satisfies the show condition, which
// narrows it again. (Measured during the board-panel spike.)
//
// The callback is always deferred: `updateNSView` runs inside SwiftUI's update pass, and callers write
// state from it — doing that synchronously is "Modifying state during view update" (see WindowAccessor).
struct WindowWidthReader: NSViewRepresentable {
    let onWidth: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onWidth: onWidth) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onWidth = onWidth
        context.coordinator.attach(to: nsView)
    }

    final class Coordinator {
        var onWidth: (CGFloat) -> Void
        private var observer: NSObjectProtocol?
        private weak var window: NSWindow?

        init(onWidth: @escaping (CGFloat) -> Void) { self.onWidth = onWidth }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

        /// Resolve the window (not available during `makeNSView`) and start watching it for resizes.
        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, let window = view.window else { return }
                self.report(window.frame.width)
                guard window !== self.window else { return }   // already watching this one
                if let observer { NotificationCenter.default.removeObserver(observer) }
                self.window = window
                self.observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: .main
                ) { [weak self] note in
                    guard let w = note.object as? NSWindow else { return }
                    self?.report(w.frame.width)
                }
            }
        }

        private func report(_ width: CGFloat) {
            MainActor.assumeIsolated { onWidth(width) }
        }
    }
}
#endif
