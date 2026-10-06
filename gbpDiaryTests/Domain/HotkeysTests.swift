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
        #expect(HotkeyAction.actions(in: "Tabs").contains(.closeTab))
    }

    @Test func resolver_overrideElseDefault() {
        let custom = Hotkey.combo("k", command: true)
        let overrides = ["closeTab": custom]
        #expect(HotkeyResolver.hotkey(for: .closeTab, overrides: overrides) == custom)
        #expect(HotkeyResolver.hotkey(for: .nextTab, overrides: overrides) == HotkeyAction.nextTab.defaultHotkey)
    }

    @Test func resolver_conflict_findsOtherActionSharingCombo() {
        // Bind Next Tab to Close Tab's default (⌘W) so the two collide.
        let overrides = ["nextTab": HotkeyAction.closeTab.defaultHotkey]
        let closeHK = HotkeyResolver.hotkey(for: .closeTab, overrides: overrides)
        #expect(HotkeyResolver.conflict(for: closeHK, excluding: .closeTab, overrides: overrides) == .nextTab)
        // No conflict for a unique combo.
        #expect(HotkeyResolver.conflict(for: .combo("x", command: true), excluding: .closeTab, overrides: overrides) == nil)
    }

    // MARK: - Store + settings

    @Test func store_setGetClear() {
        HotkeyStore.overrides = ["closeTab": .combo("k", command: true)]
        #expect(HotkeyStore.overrides["closeTab"] == .combo("k", command: true))
        HotkeyStore.overrides = [:]
        #expect(HotkeyStore.overrides.isEmpty)
    }

    @Test func settings_setResetAndCustomisedFlag() {
        HotkeyStore.overrides = [:]                 // clean slate
        let settings = HotkeySettings()
        #expect(settings.hotkey(for: .closeTab) == HotkeyAction.closeTab.defaultHotkey)
        #expect(!settings.isCustomised(.closeTab))

        let custom = Hotkey.combo("n", command: true, option: true)
        settings.setHotkey(custom, for: .closeTab)
        #expect(settings.hotkey(for: .closeTab) == custom)
        #expect(settings.isCustomised(.closeTab))

        settings.reset(.closeTab)
        #expect(settings.hotkey(for: .closeTab) == HotkeyAction.closeTab.defaultHotkey)
        #expect(!settings.isCustomised(.closeTab))
        HotkeyStore.overrides = [:]                 // don't leak into other tests
    }
}
