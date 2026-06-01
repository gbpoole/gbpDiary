import Foundation
import SwiftData

@Model final class Institution {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(inverse: \Person.institution)
    var members: [Person]
    var projects: [Project]
    @Relationship(deleteRule: .nullify, inverse: \Task.institution) var tasks: [Task]

    init(name: String, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.members = []
        self.projects = []
        self.tasks = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
