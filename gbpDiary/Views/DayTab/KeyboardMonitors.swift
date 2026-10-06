#if os(macOS)
import AppKit

// MARK: - NSEvent-level keyboard monitors
//
// onKeyPress(.delete) cannot intercept ⌫ in a TextField because NSTextField's
// deleteBackward: action fires inside interpretKeyEvents:, which SwiftUI runs
// after onKeyPress is consulted but before the closure can suppress it.
// A local NSEvent monitor fires before any responder touches the event.

final class DeleteKeyMonitor: @unchecked Sendable {
    private var monitor: Any?
    var action: (() -> Bool)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 51 else { return event }  // 51 = ⌫
            let handled = MainActor.assumeIsolated { self?.action?() ?? false }
            return handled ? nil : event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// Intercepts the Escape key to deactivate the currently focused inline field.
final class EscapeKeyMonitor: @unchecked Sendable {
    private var monitor: Any?
    var action: (() -> Bool)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }  // 53 = ⎋
            let handled = MainActor.assumeIsolated { self?.action?() ?? false }
            return handled ? nil : event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// Keys for the row-based subtask editor. One monitor rather than four, because every case needs the same
// question answered first — *is a text field being typed into?* — and that answer decides who gets the key.
//
//  • **Return / Delete / Tab** are forwarded ONLY when no NSTextView has focus, i.e. a row is *selected*
//    rather than being edited. While editing, Return reaches the TextField's `onSubmit` and Tab reaches
//    `EntryInlineKeyHandling`, exactly as they do today.
//  • **Backspace (⌫) does two jobs**, split by focus: with no field focused it deletes the *selection*
//    (on a Mac "Delete" means ⌫, so ⌦ alone would be unreachable without Fn); inside a field it removes
//    the row only when that field is EMPTY. The field editor's live string is consulted rather than the
//    model, because the row's text is pushed to SwiftData on a debounce and would still read as non-empty.
//  • **Escape** is always forwarded (it is the one key that must work mid-edit), mirroring EscapeKeyMonitor.
//
// Each closure returns true when it consumed the key, so anything unhandled falls through untouched.
final class SubtaskRowKeyMonitor: @unchecked Sendable {
    private var monitor: Any?

    var onReturn: (() -> Bool)?
    var onDelete: (() -> Bool)?
    var onTab: (() -> Bool)?
    var onBackTab: (() -> Bool)?
    /// Called with the focused field's live text when it is empty (Backspace at the start of an empty row).
    var onBackspaceInEmptyField: (() -> Bool)?
    var onEscape: (() -> Bool)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let editor = NSApp.keyWindow?.firstResponder as? NSTextView
            let isTyping = editor != nil

            let handled: Bool = MainActor.assumeIsolated {
                switch event.keyCode {
                case 53:                                        // ⎋ — must work while editing too
                    return self.onEscape?() ?? false
                case 51:                                        // ⌫ — two jobs, split by what has focus
                    guard let editor else { return self.onDelete?() ?? false }   // selection, not typing
                    guard editor.string.isEmpty else { return false }            // mid-word: leave it alone
                    return self.onBackspaceInEmptyField?() ?? false
                case 117:                                       // ⌦ (forward delete), same as ⌫ on a selection
                    guard !isTyping else { return false }
                    return self.onDelete?() ?? false
                case 36, 76:                                    // Return / numpad Enter
                    guard !isTyping else { return false }
                    return self.onReturn?() ?? false
                case 48:                                        // ⇥
                    guard !isTyping else { return false }
                    return event.modifierFlags.contains(.shift)
                        ? (self.onBackTab?() ?? false)
                        : (self.onTab?() ?? false)
                default:
                    return false
                }
            }
            return handled ? nil : event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// Intercepts Return / numpad-Enter when no NSTextView has focus (i.e. an image block
// is selected). Passes the event through when a TextEditor is active so normal newline
// insertion is unaffected.
final class ReturnKeyMonitor: @unchecked Sendable {
    private var monitor: Any?
    var action: (() -> Bool)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 36 || event.keyCode == 76 else { return event } // Return / numpad Enter
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            let handled = MainActor.assumeIsolated { self?.action?() ?? false }
            return handled ? nil : event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// Intercepts ↑/↓/←/→ and their Shift variants when no NSTextView has focus,
// to move or reorder the selected block.
final class ShiftArrowMonitor: @unchecked Sendable {
    private var monitor: Any?
    var actionUp: (() -> Bool)?         // Shift-↑: swap with block above
    var actionDown: (() -> Bool)?       // Shift-↓: swap with block below
    var actionLeft: (() -> Bool)?       // Shift-←: swap with block to left
    var actionRight: (() -> Bool)?      // Shift-→: swap with block to right
    var actionPlainUp: (() -> Bool)?    // ↑: move highlight to block above
    var actionPlainDown: (() -> Bool)?  // ↓: move highlight to block below
    var actionPlainLeft: (() -> Bool)?  // ←: move highlight to block to left
    var actionPlainRight: (() -> Bool)? // →: move highlight to block to right

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            let isShift = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
            switch event.keyCode {
            case 126:  // ↑
                let handled = MainActor.assumeIsolated {
                    isShift ? (self?.actionUp?() ?? false) : (self?.actionPlainUp?() ?? false)
                }
                return handled ? nil : event
            case 125:  // ↓
                let handled = MainActor.assumeIsolated {
                    isShift ? (self?.actionDown?() ?? false) : (self?.actionPlainDown?() ?? false)
                }
                return handled ? nil : event
            case 123:  // ←
                let handled = MainActor.assumeIsolated {
                    isShift ? (self?.actionLeft?() ?? false) : (self?.actionPlainLeft?() ?? false)
                }
                return handled ? nil : event
            case 124:  // →
                let handled = MainActor.assumeIsolated {
                    isShift ? (self?.actionRight?() ?? false) : (self?.actionPlainRight?() ?? false)
                }
                return handled ? nil : event
            default:
                return event
            }
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// Intercepts the configurable "Close Tab" shortcut (default ⌘W) so it closes the active workspace
// *tab* instead of the window. SwiftUI has no command placement to replace the standard File ▸ Close
// (⌘W), which otherwise wins and closes the window. Scoped to the workspace window via `targetWindow`:
// when the key window is something else (the Settings window, or a presented sheet), the event falls
// through to the default behaviour. `hotkey` is supplied from `HotkeySettings` and kept in sync.
final class CloseTabKeyMonitor: @unchecked Sendable {
    private var monitor: Any?
    var action: (() -> Void)?
    var hotkey: Hotkey?
    weak var targetWindow: NSWindow?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.hotkey?.matches(event) == true else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let target = self.targetWindow, event.window === target else { return false }
                self.action?()
                return true
            }
            return handled ? nil : event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// Monitors leftMouseDown and calls action when the click lands outside an NSTextView.
// Saves the focused ID (and selected block ID) before clearing so button actions can
// restore focus after mouseUp, and tap handlers can detect a second click on a selection.
final class FocusClearMonitor: @unchecked Sendable {
    private var monitor: Any?
    var action: (() -> Void)?
    var captureId: (() -> UUID?)?
    var captureSelectedId: (() -> UUID?)?
    private(set) var lastClearedId: UUID? = nil
    private(set) var lastClearedSelectedId: UUID? = nil

    func consumeLastClearedId() -> UUID? {
        defer { lastClearedId = nil }
        return lastClearedId
    }

    func consumeLastClearedSelectedId() -> UUID? {
        defer { lastClearedSelectedId = nil }
        return lastClearedSelectedId
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self,
                  let action = self.action,
                  let hit = NSApp.keyWindow?.contentView?.hitTest(event.locationInWindow),
                  !(hit is NSTextView) else { return event }
            self.lastClearedId = self.captureId?()
            self.lastClearedSelectedId = self.captureSelectedId?()
            MainActor.assumeIsolated(action)
            return event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
#endif
