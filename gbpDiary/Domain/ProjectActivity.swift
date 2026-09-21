import Foundation

// Pure "last real work" date for a project — the latest of any time-entry or focus-block date logged
// against the project's own tasks (NOT rolled up over subprojects, by design). Backs the Projects
// table's "Last Activity" column so curation can target the longest-neglected projects.
enum ProjectActivity {
    /// Latest work date across the supplied time-entry and focus-block dates; nil when nothing is logged.
    static func lastActivityAt(timeEntryDates: [Date], focusBlockDates: [Date]) -> Date? {
        (timeEntryDates + focusBlockDates).max()
    }
}
