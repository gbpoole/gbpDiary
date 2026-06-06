import Foundation
import SwiftData

@Model final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var projectDescription: String?
    @Attribute(originalName: "projectType") var stream: String?
    var tagsJSON: String
    var tags: [String] {
        get { jsonDecode([String].self, tagsJSON) ?? [] }
        set { tagsJSON = jsonEncode(newValue) }
    }
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    var parent: Project?
    @Relationship(deleteRule: .nullify, inverse: \Project.parent)
    var subprojects: [Project]

    @Relationship(inverse: \Person.devProjects)
    var devTeam: [Person]
    @Relationship(deleteRule: .nullify) var devLead: Person?

    @Relationship(inverse: \Person.sciProjects)
    var sciTeam: [Person]
    @Relationship(deleteRule: .nullify) var sciLead: Person?

    @Relationship(inverse: \Institution.projects)
    var institutions: [Institution]

    var meetings: [Minutes]
    var documents: [Document]
    @Relationship(deleteRule: .nullify, inverse: \Task.project) var tasks: [Task]
    @Relationship(deleteRule: .nullify, inverse: \Note.project) var notes: [Note]
    @Relationship(deleteRule: .nullify, inverse: \FocusBlock.project) var focusBlocks: [FocusBlock]

    init(name: String, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.stream = nil
        self.tagsJSON = "[]"
        self.isCompleted = false
        self.subprojects = []
        self.devTeam = []
        self.sciTeam = []
        self.institutions = []
        self.meetings = []
        self.documents = []
        self.tasks = []
        self.notes = []
        self.focusBlocks = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
