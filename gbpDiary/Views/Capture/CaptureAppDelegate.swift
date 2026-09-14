#if os(macOS)
import AppKit
import SwiftUI
import SwiftData

// Handles `gbpdiary://task?…` capture URLs. Using an AppKit delegate (rather than SwiftUI's `.onOpenURL` on
// the WindowGroup) means the URL is handled exactly once, app-wide, and the capture UI is a single standalone
// panel — so it never spawns an extra main window nor shows on every open window. The panel floats over
// whatever app you were in; confirming/cancelling just closes it and returns you there.
final class CaptureAppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let request = CaptureURL.parse(url) { present(request); return }
        }
    }

    private func present(_ request: CaptureURL.Request) {
        let root = QuickCaptureView(request: request, onFinish: { [weak self] in self?.close() })
            .modelContainer(gbpDiaryApp.sharedModelContainer)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = NSHostingController(rootView: root)
        panel.setContentSize(NSSize(width: 460, height: 380))
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "Quick Capture"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func close() {
        panel?.orderOut(nil)
        panel?.contentViewController = nil
    }
}
#endif
