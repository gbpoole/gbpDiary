import Foundation
import os

/// Why the meeting-import picker is showing nothing.
///
/// This exists because "it regularly fails to show a populated list" was diagnosed twice from reading
/// code and was wrong both times. An empty EventKit fetch carries **no error** — it cannot be told
/// apart from a genuinely empty stretch of calendar — so the app now records what it asked for and
/// what came back, states it under the picker, and offers a retry. A report of the failure then comes
/// with its own evidence instead of a theory.
///
/// Pure: formatting only, no EventKit.
struct CalendarImportDiagnostics {
    var access: String                  // the resolved CalendarAccess, as a word
    var windows: [(start: Date, end: Date)] = []
    var calendarsWithEvents: Int = 0
    var eventsFound: Int = 0
    var attempts: Int = 0

    /// One line for the UI caption and the log. Names the days actually queried (the end bound is
    /// exclusive, so the last *included* day is the one before it), because an unexpected window is
    /// itself a likely cause — a new meeting is anchored on the VIEWED diary day, not on today.
    func summary(calendar: Calendar = .current) -> String {
        var parts = ["access: \(access)"]
        if !windows.isEmpty {
            parts.append(windows.map { Self.describe($0, calendar: calendar) }.joined(separator: " + "))
        }
        parts.append("\(eventsFound) event\(eventsFound == 1 ? "" : "s")")
        if eventsFound > 0 {
            parts.append("\(calendarsWithEvents) calendar\(calendarsWithEvents == 1 ? "" : "s")")
        }
        if attempts > 0 { parts.append("\(attempts) attempt\(attempts == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private static func describe(_ window: (start: Date, end: Date), calendar: Calendar) -> String {
        let lastIncluded = calendar.date(byAdding: .day, value: -1, to: window.end) ?? window.end
        let fmt = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(window.start.formatted(fmt))–\(lastIncluded.formatted(fmt))"
    }
}

/// The subsystem the import load writes its one line to, so a past failure can be read back with
/// `log show --predicate 'subsystem == "io.github.gbpoole.gbpDiary"'`.
enum CalendarImportLog {
    private static let logger = Logger(subsystem: "io.github.gbpoole.gbpDiary", category: "calendar-import")

    /// Call sites pass the finished line, so `os` stays imported here only (Swift 6 requires the
    /// defining module at every use of a `Logger` interpolation).
    static func record(_ line: String) {
        logger.info("meeting import — \(line, privacy: .public)")
    }
}

/// `.task(id:)` key: reload when the meeting is re-dated **or** when Retry is pressed.
struct CalendarLoadKey: Equatable {
    let anchor: Date
    let attempt: Int
}
