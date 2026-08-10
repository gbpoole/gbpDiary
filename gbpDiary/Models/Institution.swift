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

    // Comparable sort keys for the Institutions table columns (see the List/Table page style in CLAUDE.md).
    var nameKey: String { name.lowercased() }
    var memberCount: Int { members.count }
    var projectCount: Int { projects.count }

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
