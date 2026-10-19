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

    private static let lastTimesheetExportKey = "timesheet.lastExportPath"

    /// The JSON file written by the most recent Timesheet export. Exports go only where the user chose, so
    /// nothing accumulates in the app container — this POINTER is how an external reader (the MCP server)
    /// still finds the latest figures.
    static var lastTimesheetExportPath: String? {
        get { UserDefaults.standard.string(forKey: lastTimesheetExportKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastTimesheetExportKey) }
    }

    private static let taskPanelShownKey = "diaryTaskPanelShown"

    /// Whether the diary's right-hand task panel is shown (defaults to true on first launch).
    static var taskPanelShown: Bool {
        get { UserDefaults.standard.object(forKey: taskPanelShownKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: taskPanelShownKey) }
    }
}
