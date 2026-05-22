import Foundation
import SwiftData

@Model final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var projectDescription: String?
    var projectType: String?
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    var parent: Project?
    @Relationship(deleteRule: .nullify)
    var subprojects: [Project]

    @Relationship(inverse: \Person.devProjects)
    var devTeam: [Person]

    @Relationship(inverse: \Person.sciProjects)
    var sciTeam: [Person]

    @Relationship(inverse: \Institution.projects)
    var institutions: [Institution]

    var meetings: [Minutes]
    var documents: [Document]

    init(name: String, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.isCompleted = false
        self.subprojects = []
        self.devTeam = []
        self.sciTeam = []
        self.institutions = []
        self.meetings = []
        self.documents = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
