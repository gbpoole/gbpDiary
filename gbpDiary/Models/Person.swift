import Foundation
import SwiftData

@Model final class Person {
    @Attribute(.unique) var id: UUID
    var name: String
    var email: String?
    var tagsJSON: String
    var tags: [String] {
        get { jsonDecode([String].self, tagsJSON) ?? [] }
        set { tagsJSON = jsonEncode(newValue) }
    }
    var createdAt: Date
    var updatedAt: Date

    var institution: Institution?
    var devProjects: [Project]
    var sciProjects: [Project]
    var minutesAttended: [Minutes]
    @Relationship(deleteRule: .nullify, inverse: \Task.assignee) var tasks: [Task]

    init(name: String, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.tagsJSON = "[]"
        self.devProjects = []
        self.sciProjects = []
        self.minutesAttended = []
        self.tasks = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
