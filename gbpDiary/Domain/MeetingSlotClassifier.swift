import Foundation

enum MeetingSlotClassifier {
    static func slots(for minutes: Minutes, on date: Date, calendar: Calendar = .current) -> Set<DaySlot> {
        let boundary = DaySlotBoundary.morningAfternoon(on: date, calendar: calendar)
        let start = minutes.meetingAt
        let end: Date = minutes.duration.map {
            start.addingTimeInterval($0.hoursNormalized * 3600)
        } ?? start

        var result: Set<DaySlot> = []
        if start < boundary { result.insert(.morning) }
        if end >= boundary  { result.insert(.afternoon) }
        return result
    }
}
