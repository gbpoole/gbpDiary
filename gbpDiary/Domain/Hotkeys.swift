import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// A configurable keyboard shortcut: a base key plus modifier flags. Persisted (Codable), rendered as a
// SwiftUI `.keyboardShortcut` for menu commands, and matched at the NSEvent level for shortcuts handled
// by a monitor (e.g. Close Tab / CloseTabKeyMonitor). The base key is stored lowercased.
struct Hotkey: Codable, Equatable, Hashable {
    var key: String
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    static func combo(_ key: String, command: Bool = false, shift: Bool = false,
                      option: Bool = false, control: Bool = false) -> Hotkey {
        Hotkey(key: key.lowercased(), command: command, shift: shift, option: option, control: control)
    }

    /// A shortcut is only usable as an app command when it carries at least one non-shift modifier.
    var isValid: Bool { !key.isEmpty && (command || control || option) }

    // MARK: SwiftUI

    var keyEquivalent: KeyEquivalent? {
        guard let ch = key.first else { return nil }
        return KeyEquivalent(ch)
    }

    var eventModifiers: EventModifiers {
        var m: EventModifiers = []
        if command { m.insert(.command) }
        if shift { m.insert(.shift) }
        if option { m.insert(.option) }
        if control { m.insert(.control) }
        return m
    }

    /// A `KeyboardShortcut` for a menu command, or nil when the key is empty.
    var keyboardShortcut: KeyboardShortcut? {
        guard let ke = keyEquivalent else { return nil }
        return KeyboardShortcut(ke, modifiers: eventModifiers)
    }

    /// Human-readable form like "⌘⇧]".
    var display: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        s += key.uppercased()
        return s
    }
}

#if canImport(AppKit)
extension Hotkey {
    /// Build a hotkey from a captured key-down event (used by the recorder). Uses
    /// `charactersIgnoringModifiers` so recording and NSEvent matching stay symmetric.
    init(event: NSEvent) {
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let flags = event.modifierFlags
        self.init(key: chars,
                  command: flags.contains(.command), shift: flags.contains(.shift),
                  option: flags.contains(.option), control: flags.contains(.control))
    }

    /// Whether a key-down event matches this hotkey (exact modifier set, same base key).
    func matches(_ event: NSEvent) -> Bool {
        guard !key.isEmpty,
              let chars = event.charactersIgnoringModifiers?.lowercased(), chars == key else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        var want: NSEvent.ModifierFlags = []
        if command { want.insert(.command) }
        if shift { want.insert(.shift) }
        if option { want.insert(.option) }
        if control { want.insert(.control) }
        return flags == want
    }
}
#endif

// MARK: - Actions

// The app-specific commands whose shortcuts are user-configurable. Each case is a stable id (for
// persistence), a display title, a section heading (for grouping in Settings), and a default hotkey.
// ANY new app-specific hotkey MUST be added here (under an appropriate `section`) rather than hardcoded,
// so it appears in Settings ▸ Shortcuts — see CLAUDE.md.
enum HotkeyAction: String, CaseIterable, Identifiable {
    case newTab
    case closeTab
    case nextTab
    case previousTab
    case previousActiveTab
    case lastTab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newTab:            "New Tab"
        case .closeTab:          "Close Tab"
        case .nextTab:           "Show Next Tab"
        case .previousTab:       "Show Previous Tab"
        case .previousActiveTab: "Return to Previous Tab"
        case .lastTab:           "Show Last Tab"
        }
    }

    /// Section heading under which this shortcut is grouped in Settings.
    var section: String {
        switch self {
        case .newTab, .closeTab, .nextTab, .previousTab, .previousActiveTab, .lastTab: "Tabs"
        }
    }

    var defaultHotkey: Hotkey {
        switch self {
        case .newTab:            .combo("n", command: true)
        case .closeTab:          .combo("w", command: true)
        case .nextTab:           .combo("]", command: true, shift: true)
        case .previousTab:       .combo("[", command: true, shift: true)
        // Option-variant of the positional ⌘⇧[ : Shift = by position, Option = by recency.
        case .previousActiveTab: .combo("[", command: true, option: true)
        case .lastTab:           .combo("9", command: true)
        }
    }

    /// Section headings in display order.
    static var sections: [String] {
        var seen = Set<String>()
        return allCases.compactMap { seen.insert($0.section).inserted ? $0.section : nil }
    }

    static func actions(in section: String) -> [HotkeyAction] {
        allCases.filter { $0.section == section }
    }
}

// MARK: - Resolution (pure)

// Pure resolution of the effective hotkey for an action given the stored overrides, plus conflict
// detection. Kept free of UserDefaults so it is unit-testable.
enum HotkeyResolver {
    static func hotkey(for action: HotkeyAction, overrides: [String: Hotkey]) -> Hotkey {
        overrides[action.id] ?? action.defaultHotkey
    }

    /// The first other action already bound to `hotkey`, or nil if none — used to warn about conflicts.
    static func conflict(for hotkey: Hotkey, excluding action: HotkeyAction,
                         overrides: [String: Hotkey]) -> HotkeyAction? {
        HotkeyAction.allCases.first { $0 != action && self.hotkey(for: $0, overrides: overrides) == hotkey }
    }
}

// MARK: - Store

/// Persists per-action hotkey overrides as JSON in UserDefaults (mirrors AppSettingsStore). An action
/// with no override uses its `defaultHotkey`.
enum HotkeyStore {
    private static let key = "hotkeyOverrides"

    static var overrides: [String: Hotkey] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([String: Hotkey].self, from: data) else { return [:] }
            return decoded
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}

// MARK: - Observable settings

/// App-wide, observable hotkey bindings. Injected via `.environment` and read by `AppCommands`
/// (menu shortcuts), `CloseTabKeyMonitor` (⌘W-style capture), and the Settings ▸ Shortcuts pane.
@MainActor
@Observable
final class HotkeySettings {
    private var overrides: [String: Hotkey]

    init() { overrides = HotkeyStore.overrides }

    func hotkey(for action: HotkeyAction) -> Hotkey {
        HotkeyResolver.hotkey(for: action, overrides: overrides)
    }

    func setHotkey(_ hotkey: Hotkey, for action: HotkeyAction) {
        overrides[action.id] = hotkey
        persist()
    }

    /// Revert an action to its default (removes any override).
    func reset(_ action: HotkeyAction) {
        overrides.removeValue(forKey: action.id)
        persist()
    }

    func resetAll() {
        overrides.removeAll()
        persist()
    }

    func isCustomised(_ action: HotkeyAction) -> Bool { overrides[action.id] != nil }

    func conflict(for hotkey: Hotkey, excluding action: HotkeyAction) -> HotkeyAction? {
        HotkeyResolver.conflict(for: hotkey, excluding: action, overrides: overrides)
    }

    private func persist() { HotkeyStore.overrides = overrides }
}
