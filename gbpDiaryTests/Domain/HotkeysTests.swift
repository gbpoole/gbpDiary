import Foundation
import SwiftUI
import Testing
@testable import gbpDiary

@MainActor
struct HotkeysTests {
    // MARK: - Hotkey value type

    @Test func hotkey_codableRoundTrips() throws {
        let hk = Hotkey.combo("]", command: true, shift: true)
        let data = try JSONEncoder().encode(hk)
        #expect(try JSONDecoder().decode(Hotkey.self, from: data) == hk)
    }

    @Test func hotkey_display_ordersModifiers() {
        // Apple's canonical modifier order is ⌃⌥⇧⌘ (Command adjacent to the key).
        #expect(Hotkey.combo("t", command: true).display == "⌘T")
        #expect(Hotkey.combo("]", command: true, shift: true).display == "⇧⌘]")
        #expect(Hotkey.combo("k", command: true, option: true, control: true).display == "⌃⌥⌘K")
    }

    @Test func hotkey_isValid_requiresNonShiftModifier() {
        #expect(Hotkey.combo("t", command: true).isValid)
        #expect(Hotkey.combo("f", control: true).isValid)
        #expect(!Hotkey.combo("a").isValid)              // bare key
        #expect(!Hotkey.combo("a", shift: true).isValid) // shift alone isn't a command modifier
        #expect(!Hotkey.combo("", command: true).isValid) // empty key
    }

    @Test func hotkey_keyEquivalentAndModifiers() {
        let hk = Hotkey.combo("]", command: true, shift: true)
        #expect(hk.keyEquivalent?.character == "]")
        #expect(hk.eventModifiers.contains(.command))
        #expect(hk.eventModifiers.contains(.shift))
        #expect(!hk.eventModifiers.contains(.option))
    }

    // MARK: - Actions + resolver

    @Test func actions_haveUniqueIdsValidDefaultsAndSections() {
        let ids = HotkeyAction.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)                       // unique ids
        for action in HotkeyAction.allCases {
            #expect(action.defaultHotkey.isValid)                  // every default is a usable command
            #expect(!action.section.isEmpty)
        }
        #expect(HotkeyAction.sections == ["Tabs"])                 // current headings
        #expect(HotkeyAction.actions(in: "Tabs").contains(.newTab))
    }

    @Test func resolver_overrideElseDefault() {
        let custom = Hotkey.combo("n", command: true)
        let overrides = ["newTab": custom]
        #expect(HotkeyResolver.hotkey(for: .newTab, overrides: overrides) == custom)
        #expect(HotkeyResolver.hotkey(for: .closeTab, overrides: overrides) == HotkeyAction.closeTab.defaultHotkey)
    }

    @Test func resolver_conflict_findsOtherActionSharingCombo() {
        // Bind Next Tab to ⌘T, which collides with New Tab's default.
        let overrides = ["nextTab": Hotkey.combo("t", command: true)]
        let newTabHK = HotkeyResolver.hotkey(for: .newTab, overrides: overrides)
        #expect(HotkeyResolver.conflict(for: newTabHK, excluding: .newTab, overrides: overrides) == .nextTab)
        // No conflict for a unique combo.
        #expect(HotkeyResolver.conflict(for: .combo("x", command: true), excluding: .newTab, overrides: overrides) == nil)
    }

    // MARK: - Store + settings

    @Test func store_setGetClear() {
        HotkeyStore.overrides = ["newTab": .combo("n", command: true)]
        #expect(HotkeyStore.overrides["newTab"] == .combo("n", command: true))
        HotkeyStore.overrides = [:]
        #expect(HotkeyStore.overrides.isEmpty)
    }

    @Test func settings_setResetAndCustomisedFlag() {
        HotkeyStore.overrides = [:]                 // clean slate
        let settings = HotkeySettings()
        #expect(settings.hotkey(for: .newTab) == HotkeyAction.newTab.defaultHotkey)
        #expect(!settings.isCustomised(.newTab))

        let custom = Hotkey.combo("n", command: true, option: true)
        settings.setHotkey(custom, for: .newTab)
        #expect(settings.hotkey(for: .newTab) == custom)
        #expect(settings.isCustomised(.newTab))

        settings.reset(.newTab)
        #expect(settings.hotkey(for: .newTab) == HotkeyAction.newTab.defaultHotkey)
        #expect(!settings.isCustomised(.newTab))
        HotkeyStore.overrides = [:]                 // don't leak into other tests
    }
}
