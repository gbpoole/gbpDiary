import Foundation
import SwiftData
@testable import gbpDiary

enum TestModelContainer {
    static func make() throws -> ModelContainer {
        let schema = Schema([
            Task.self,
            DayRecord.self,
            DayEntry.self,
            Project.self,
            Person.self,
            Institution.self,
            Minutes.self,
            Attachment.self,
            Document.self,
            Note.self,
            TaskTimeEntry.self,
            FocusBlock.self,
            EmailMessage.self,
            EmailThreadSummary.self,
            EmailConversation.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

enum FixedDates {
    static let reference = Date(timeIntervalSince1970: 1_700_000_000)

    static func dayStart(offsetDays: Int = 0, calendar: Calendar = .current) -> Date {
        let base = calendar.startOfDay(for: reference)
        return calendar.date(byAdding: .day, value: offsetDays, to: base) ?? base
    }

    static func atHour(_ hour: Int, onDayOffset dayOffset: Int = 0, calendar: Calendar = .current) -> Date {
        let start = dayStart(offsetDays: dayOffset, calendar: calendar)
        return calendar.date(byAdding: .hour, value: hour, to: start) ?? start
    }
}
