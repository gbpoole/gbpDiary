import Foundation

// Persistent state for the Diary browsing surface. Held at the workspace level so the selected
// date and Day/Week mode survive switching to another tab (e.g. an open meeting) and back —
// DiaryView itself is recreated on tab switch and must not own this in transient @State.
@Observable final class DiaryState {
    var currentDate: Date = Calendar.current.startOfDay(for: Date())
    var mode: DiaryMode = .day
}
