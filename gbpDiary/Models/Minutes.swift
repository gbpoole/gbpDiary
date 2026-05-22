import Foundation
import SwiftData

@Model final class Minutes {
    @Attribute(.unique) var id: UUID
    var meetingAt: Date
    var summary: String?
    var minutesContent: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(inverse: \Project.meetings)
    var projects: [Project]

    @Relationship(inverse: \Person.minutesAttended)
    var attendees: [Person]

    init(meetingAt: Date, id: UUID = UUID()) {
        self.id = id
        self.meetingAt = meetingAt
        self.projects = []
        self.attendees = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
