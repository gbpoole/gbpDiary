import SwiftUI
#if os(macOS)
import AppKit
#endif

// Shared identifiers + opener for the macOS Settings window's tabs. The TabView binds its selection to
// `@AppStorage(SettingsTab.storageKey)`, so setting that key selects a tab; `open(_:)` also brings the
// Settings window forward. Lets in-app buttons deep-link to a specific settings tab.
enum SettingsTab {
    static let storageKey = "settings.selectedTab"
    static let general = "general"
    static let calendar = "calendar"
    static let email = "email"

    /// Select `tab` and open/bring-forward the Settings window (macOS).
    static func open(_ tab: String) {
        UserDefaults.standard.set(tab, forKey: storageKey)
        #if os(macOS)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        #endif
    }
}
