import Foundation
import SwiftData

// Time-of-day boundaries and slot classification for activity/time entries.
//
// Morning ends at 12:30. Afternoon runs until an (optional) evening block's flexible start time —
// evening only exists when the user has created an evening block for the day. Evening time is
// overtime. There is no "unspecified" slot: every instant maps to morning, afternoon, or evening.
enum DaySlotBoundary {
    static let morningEndHour = 12
    static let morningEndMinute = 30

    static func morningAfternoon(on date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: morningEndHour, minute: morningEndMinute, second: 0, of: date) ?? date
    }
}

enum DaySlotClassifier {
    /// The slot an instant falls in. `eveningStart` is the day's evening-block start time, or nil
    /// when there is no evening block (so nothing classifies as evening).
    static func slot(for instant: Date, eveningStart: Date?, calendar: Calendar = .current) -> DaySlot {
        if let eveningStart, instant >= eveningStart { return .evening }
        return instant < DaySlotBoundary.morningAfternoon(on: instant, calendar: calendar) ? .morning : .afternoon
    }
}

// Finds the focus block whose range contains an entry's time, or nil when the time lies outside
// every existing block (those entries render standalone). Evening takes precedence; morning/
// afternoon fall back to an all-day block. Nothing is auto-created — blocks are user-defined ranges.
@MainActor
enum FocusBlockAssignment {
    static func containingBlock(for date: Date, blocks: [FocusBlock], calendar: Calendar = .current) -> FocusBlock? {
        let eveningBlock = blocks.first { $0.slot == .evening }
        let slot = DaySlotClassifier.slot(for: date, eveningStart: eveningBlock?.startTime, calendar: calendar)
        if slot == .evening { return eveningBlock }
        if let match = blocks.first(where: { $0.slot == slot }) { return match }
        return blocks.first(where: { $0.slot == .allDay })
    }
}

// Focus-block capacity math. Net-remaining = the block's capacity minus the hours logged into it
// (its time-derived entries plus any meetings), clamped to zero. Pure so it can be unit-tested;
// the block's activities are never stored (membership is derived by time — FocusBlockAssignment).
enum FocusBlockMath {
    static func netHours(capacity: Double, loggedHours: Double) -> Double {
        max(0, capacity - loggedHours)
    }
}
