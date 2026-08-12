import Foundation

// Small app-wide preferences persisted in UserDefaults. Currently just "me" — the Person used as the
// default assignee for new meeting action items.
enum AppSettingsStore {
    private static let mePersonKey = "mePersonID"

    static var myPersonID: UUID? {
        get { UserDefaults.standard.string(forKey: mePersonKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: mePersonKey) }
    }

    private static let defaultCalendarIDsKey = "defaultCalendarIDs"

    /// Calendar identifiers pre-selected when importing an event into a new meeting (empty = all).
    static var defaultCalendarIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: defaultCalendarIDsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: defaultCalendarIDsKey) }
    }

    private static let pagePaletteKey = "pagePalette"

    /// The colour theme used when exporting minutes/notes to PDF (Settings ▸ Appearance).
    static var pagePalette: ExportPalette {
        get { UserDefaults.standard.string(forKey: pagePaletteKey).flatMap(ExportPalette.init) ?? .lightShaded }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: pagePaletteKey) }
    }
}
