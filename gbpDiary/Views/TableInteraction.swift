import SwiftUI

// Shared list/table interaction helpers used by every macOS Table page.
//
// `onTableRowDoubleClick` gives a SwiftUI `Table` **native single-click selection** plus
// **double-click to open**, without attaching a SwiftUI tap gesture to any cell (a cell tap gesture
// competes with NSTableView's own mouse handling and makes single-click selection unreliable).
extension View {
    /// Calls `open(rowIndex)` when a row of the enclosing macOS `Table` is double-clicked. `rowIndex`
    /// is the NSTableView row, which matches the page's sorted display array. No-op on iOS.
    func onTableRowDoubleClick(_ open: @escaping (Int) -> Void) -> some View {
        #if os(macOS)
        modifier(TableDoubleClickModifier(open: open))
        #else
        self
        #endif
    }
}

#if os(macOS)
import AppKit

private struct TableDoubleClickModifier: ViewModifier {
    let open: (Int) -> Void

    @State private var monitor = TableDoubleClickMonitor()
    @State private var pendingRow: Int? = nil

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor.onRow = { row in pendingRow = row }
                monitor.start()
            }
            .onDisappear { monitor.stop() }
            .onChange(of: pendingRow) { _, new in
                if let row = new { open(row); pendingRow = nil }
            }
    }
}

// Detects a double-click on a SwiftUI `Table`'s backing `NSTableView` without interfering with native
// selection. Watches `leftMouseDown` at the NSEvent level (like `FocusClearMonitor`), hit-tests the
// clicked view up to its enclosing NSTableView, and reports the clicked row — always returning the
// event unmodified so the table's own selection still happens.
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
                  table.numberOfColumns > 1              // a list-page Table is multi-column; the sidebar list isn't
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
