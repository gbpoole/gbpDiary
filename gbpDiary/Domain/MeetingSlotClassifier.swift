import Foundation

enum MeetingSlotClassifier {
    static func slots(for minutes: Minutes, on date: Date, calendar: Calendar = .current) -> Set<DaySlot> {
        guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) else {
            return [.allDay]
        }
        let start = minutes.meetingAt
        let end: Date = minutes.duration.map {
            start.addingTimeInterval($0.hoursNormalized * 3600)
        } ?? start

        var result: Set<DaySlot> = []
        if start < noon { result.insert(.morning) }
        if end >= noon  { result.insert(.afternoon) }
        return result
    }
}
