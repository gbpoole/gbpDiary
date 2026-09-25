#if os(macOS)
import AppKit

// Tracks whether a board card is currently being dragged.
//
// SwiftUI gives no "drag ended" callback: `.onDrag` fires at the start, but a drag that is cancelled
// or dropped on nothing reports nothing back, so a flag set at the start would stay set. Mouse-up ends
// every drag, so an NSEvent monitor is the reliable way to clear it — the same technique the app
// already uses for key handling (see KeyboardMonitors.swift).
final class BoardDragMonitor: @unchecked Sendable {
    private var localMonitor: Any?
    private var globalMonitor: Any?

    /// Called on mouse-up, i.e. whenever any drag has finished, however it ended.
    var onEnded: (() -> Void)?

    func start() {
        guard localMonitor == nil, globalMonitor == nil else { return }
        // Local catches a drop inside our own windows; global catches one released elsewhere.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.fire()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.fire()
        }
    }

    func stop() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    private func fire() {
        MainActor.assumeIsolated { onEnded?() }
    }
}
#endif
