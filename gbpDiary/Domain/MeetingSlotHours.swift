import Foundation

// How much of a meeting falls inside a given day slot, so a meeting spanning the 12:30 morning/afternoon
// boundary is counted by its in-slot portion in each focus block (not double-counted at full duration in both).
// Morning = [startOfDay, 12:30); afternoon = [12:30, endOfDay); allDay/evening = the whole meeting (allDay is
// never split, and meetings don't land in evening/overtime blocks). Pure + tested.
nonisolated enum MeetingSlotHours {
    static func overlapHours(start: Date, durationHours: Double, slot: DaySlot,
                             on date: Date, calendar: Calendar = .current) -> Double {
        guard durationHours > 0 else { return 0 }
        let end = start.addingTimeInterval(durationHours * 3600)

        let (lower, upper): (Date, Date)
        switch slot {
        case .allDay, .evening:
            return durationHours   // not split
        case .morning:
            let dayStart = calendar.startOfDay(for: date)
            lower = dayStart
            upper = DaySlotBoundary.morningAfternoon(on: date, calendar: calendar)
        case .afternoon:
            let dayStart = calendar.startOfDay(for: date)
            lower = DaySlotBoundary.morningAfternoon(on: date, calendar: calendar)
            upper = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? end
        }

        let overlapStart = max(start, lower)
        let overlapEnd = min(end, upper)
        let seconds = overlapEnd.timeIntervalSince(overlapStart)
        return seconds > 0 ? seconds / 3600 : 0
    }
}
