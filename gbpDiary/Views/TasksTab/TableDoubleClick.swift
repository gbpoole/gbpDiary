#if os(macOS)
import AppKit

// Detects a double-click on a SwiftUI `Table`'s backing `NSTableView` without interfering with
// native selection. A SwiftUI tap gesture on a Table cell competes with NSTableView's own mouse
// handling (it holds each click to see whether a second one follows), making single-click selection
// unreliable. Instead we watch `leftMouseDown` at the NSEvent level (like `FocusClearMonitor`),
// hit-test the clicked view up to its enclosing NSTableView, and report the clicked row — always
// returning the event unmodified so the table's own selection still happens.
final class TableDoubleClickMonitor: @unchecked Sendable {
    private var monitor: Any?
    var onRow: ((Int) -> Void)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self,
                  event.clickCount == 2,
                  let onRow = self.onRow,
                  let hit = event.window?.contentView?.hitTest(event.locationInWindow),
                  let table = Self.enclosingTableView(hit),
                  table.numberOfColumns > 1              // the Tasks table is multi-column; the sidebar list isn't
            else { return event }
            let point = table.convert(event.locationInWindow, from: nil)
            let row = table.row(at: point)
            guard row >= 0 else { return event }
            MainActor.assumeIsolated { onRow(row) }
            return event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private static func enclosingTableView(_ view: NSView) -> NSTableView? {
        var current: NSView? = view
        while let v = current {
            if let table = v as? NSTableView { return table }
            current = v.superview
        }
        return nil
    }
}
#endif
