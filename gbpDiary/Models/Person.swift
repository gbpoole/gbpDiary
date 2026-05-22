import Foundation
import SwiftData

@Model final class Person {
    @Attribute(.unique) var id: UUID
    var name: String
    var email: String?
    var createdAt: Date
    var updatedAt: Date

    var institution: Institution?
    var devProjects: [Project]
    var sciProjects: [Project]
    var minutesAttended: [Minutes]

    init(name: String, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.devProjects = []
        self.sciProjects = []
        self.minutesAttended = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
