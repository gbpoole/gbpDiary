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
    var emails: [EmailMessage]
    @Relationship(deleteRule: .nullify, inverse: \Task.project) var tasks: [Task]
    @Relationship(deleteRule: .nullify, inverse: \Note.project) var notes: [Note]
    @Relationship(deleteRule: .nullify, inverse: \FocusBlock.project) var focusBlocks: [FocusBlock]

    // Comparable sort keys for the Projects table columns (see the List/Table page style in CLAUDE.md).
    // `teamKey` also backs the Dev/Sci Team cell display so ordering and text stay in sync.
    var nameKey: String { name.lowercased() }
    var streamKey: String { (stream ?? "").lowercased() }
    var subprojectCount: Int { subprojects.count }
    var lastMeetingAt: Date { meetings.map(\.meetingAt).max() ?? .distantPast }
    var devTeamKey: String { Project.teamKey(lead: devLead, team: devTeam) }
    var sciTeamKey: String { Project.teamKey(lead: sciLead, team: sciTeam) }

    static func teamKey(lead: Person?, team: [Person]) -> String {
        teamNames(lead: lead, team: team).joined(separator: ", ").lowercased()
    }

    // Lead first, then the remaining members alphabetically — shared by the cell text and the sort key.
    static func teamNames(lead: Person?, team: [Person]) -> [String] {
        let leadNames = lead.map { [$0.name] } ?? []
        let others = team.filter { $0.id != lead?.id }.map(\.name).sorted()
        return leadNames + others
    }

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
        self.emails = []
        self.tasks = []
        self.notes = []
        self.focusBlocks = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}
