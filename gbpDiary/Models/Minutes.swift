import Foundation
import SwiftData

@Model final class Minutes {
    @Attribute(.unique) var id: UUID
    var meetingAt: Date
    var summary: String?
    var minutesContent: String?
    var duration: Duration?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(inverse: \Project.meetings)
    var projects: [Project]

    @Relationship(inverse: \Person.minutesAttended)
    var attendees: [Person]

    @Relationship(deleteRule: .nullify, inverse: \Task.originMinutes)
    var newTasks: [Task]

    @Relationship(deleteRule: .cascade, inverse: \Note.minutes)
    var note: Note? = nil

    @Relationship(inverse: \Document.meetings)
    var documents: [Document] = []

    // Comparable sort keys for the Minutes table columns (see the List/Table page style in CLAUDE.md).
    // The Date/Time columns sort by `meetingAt` directly.
    var summaryKey: String { (summary ?? "").lowercased() }
    var projectsKey: String { projects.map(\.name).sorted().joined(separator: ", ").lowercased() }
    var attendeeCount: Int { attendees.count }

    init(meetingAt: Date, id: UUID = UUID()) {
        self.id = id
        self.meetingAt = meetingAt
        self.projects = []
        self.attendees = []
        self.newTasks = []
        self.documents = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
