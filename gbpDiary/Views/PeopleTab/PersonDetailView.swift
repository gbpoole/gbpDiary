import SwiftUI
import SwiftData

// A rich person page (workspace tab), styled like the individual project page (ProjectDetailView): a
// pinned title + inline-editable metadata card, then scrolling sections for the person's assigned tasks,
// team projects, and attended meetings. Metadata edits are live — no separate editor sheet.
struct PersonDetailView: View {
    @Bindable var person: Person
    var asSheet: Bool = false

    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query(sort: \Minutes.meetingAt, order: .reverse) private var allMinutes: [Minutes]
    @Query(sort: \Institution.name) private var institutions: [Institution]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceModel.self) private var workspace

    @State private var editingTask: Task?
    @State private var showCompleted = false
    @State private var tagsText = ""

    private var openTasks: [Task] {
        allTasks.filter { $0.assignee?.id == person.id && ($0.status == .todo || $0.status == .started) }
    }
    private var completedTasks: [Task] {
        allTasks.filter { $0.assignee?.id == person.id && $0.status == .completed }
    }
    private var attendedMeetings: [Minutes] {
        allMinutes.filter { $0.attendees.contains { $0.id == person.id } }
    }

    var body: some View {
        if asSheet {
            NavigationStack { coreContent }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 480)
            #endif
        } else {
            coreContent
        }
    }

    private var coreContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pinned header (like the project and meeting-minutes pages); sections scroll below.
            header
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("Open Tasks (\(openTasks.count))") { openTasksContent }
                    section("Projects (\(person.teamProjects.count))") { projectsContent }
                    section("Meetings (\(attendedMeetings.count))") { meetingsContent }
                    if !completedTasks.isEmpty { completedTasksSection }
                }
                .padding(.bottom, 28)
            }
        }
        .background(AppTheme.background)
        .navigationTitle(person.name)
        .onAppear { tagsText = person.tags.joined(separator: ", ") }
        .toolbar {
            if asSheet {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheet(item: $editingTask) { t in TaskEditorSheet(task: t, defaultDate: Date()) }
    }

    // MARK: - Header (title + a minutes-style inline-editable metadata card)

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(person.name.isEmpty ? "Unnamed" : person.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.text)
            metadataCard
        }
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            metaRow("Name") {
                TextField("Name", text: nameBinding)
                    .textFieldStyle(.roundedBorder)
            }
            metaRow("Emails", alignment: .top) {
                EmailListEditor(emails: emailsBinding)
            }
            metaRow("Institution") {
                FuzzyPickerField(
                    allItems: institutions,
                    selectedItem: institutionBinding,
                    label: { $0.name },
                    chipColor: AppTheme.institution,
                    onCreateItem: { makeInstitution($0) },
                    tapArea: true,
                    emptyLabel: "None — tap to choose or add"
                )
            }
            metaRow("Tags") {
                TextField("Comma-separated tags", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: tagsText) { _, newValue in
                        person.tags = newValue.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        person.updatedAt = Date()
                    }
            }
        }
        .padding(10)
        .background(AppTheme.cardRaised.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metaRow<Content: View>(_ label: String,
                                        alignment: VerticalAlignment = .firstTextBaseline,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: alignment, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { person.name },
                set: { person.name = $0; person.updatedAt = Date() })
    }
    private var emailsBinding: Binding<[String]> {
        Binding(get: { person.emails },
                set: { person.emails = $0; person.updatedAt = Date() })
    }
    private var institutionBinding: Binding<Institution?> {
        Binding(get: { person.institution },
                set: { person.institution = $0; person.updatedAt = Date() })
    }

    private func makeInstitution(_ name: String) -> Institution? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let inst = Institution(name: trimmed)
        modelContext.insert(inst)
        return inst
    }

    // MARK: - Sections

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        DaySectionHeader(title: title)
        VStack(alignment: .leading, spacing: 4) { content() }
            .padding(.horizontal)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text).foregroundStyle(AppTheme.mutedText).font(.callout).padding(.vertical, 2)
    }

    @ViewBuilder private var openTasksContent: some View {
        if openTasks.isEmpty {
            emptyLine("No open tasks.")
        } else {
            ForEach(openTasks) { task in TaskRowView(task: task, onEdit: { editingTask = task }) }
        }
    }

    @ViewBuilder private var projectsContent: some View {
        if person.teamProjects.isEmpty {
            emptyLine("Not a team member of any project.")
        } else {
            ForEach(person.teamProjects) { project in
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(AppTheme.project).font(.system(size: 12)).frame(width: 18)
                    Text(project.name).foregroundStyle(AppTheme.text).lineLimit(1)
                    Chip(label: roleLabel(for: project), color: AppTheme.person)
                    if isLead(of: project) { Chip(label: "Lead", color: AppTheme.followUp) }
                    if project.isCompleted { Chip(label: "Completed", color: AppTheme.mutedText) }
                    Spacer()
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { workspace.focusOrOpen(.project(project.persistentModelID)) }
            }
        }
    }

    private func roleLabel(for project: Project) -> String {
        let dev = project.devTeam.contains { $0.id == person.id }
        let sci = project.sciTeam.contains { $0.id == person.id }
        if dev && sci { return "Dev · Sci" }
        return sci ? "Sci" : "Dev"
    }

    private func isLead(of project: Project) -> Bool {
        project.devLead?.id == person.id || project.sciLead?.id == person.id
    }

    @ViewBuilder private var meetingsContent: some View {
        if attendedMeetings.isEmpty {
            emptyLine("No meetings attended.")
        } else {
            ForEach(attendedMeetings) { meeting in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.3.sequence")
                        .foregroundStyle(AppTheme.project).font(.system(size: 12))
                        .frame(width: 18).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(meeting.summary?.isEmpty == false ? meeting.summary! : "Meeting")
                            .foregroundStyle(AppTheme.text).lineLimit(1)
                        Text(meetingCaption(meeting))
                            .font(.caption).foregroundStyle(AppTheme.mutedText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { workspace.openInNewTab(.minutes(meeting.persistentModelID)) }
            }
        }
    }

    private func meetingCaption(_ meeting: Minutes) -> String {
        let date = meeting.meetingAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        let projects = meeting.projects.map(\.name).joined(separator: ", ")
        return projects.isEmpty ? date : "\(date) · \(projects)"
    }

    // Completed tasks are useful but rarely needed — collapsed by default (mirrors ProjectDetailView).
    private var completedTasksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $showCompleted) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(completedTasks) { task in TaskRowView(task: task, onEdit: { editingTask = task }) }
                }
                .padding(.top, 4)
            } label: {
                Text("Completed Tasks (\(completedTasks.count))")
                    .font(AppTheme.interfaceFont(size: 12, weight: .semibold))
                    .tracking(0.8).textCase(.uppercase)
                    .foregroundStyle(AppTheme.mutedText)
            }
            .tint(AppTheme.mutedText)
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }
}
