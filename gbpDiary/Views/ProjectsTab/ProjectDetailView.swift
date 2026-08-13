import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    @Bindable var project: Project
    var asSheet: Bool = false

    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query(sort: \Note.createdAt) private var allNotes: [Note]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceModel.self) private var workspace

    @State private var showingAddMinutes = false
    @State private var addingSubproject = false
    @State private var editingTask: Task?
    @State private var editingNote: Note?
    @State private var editingDocument: Document?
    @State private var showCompleted = false
    @State private var tagsText = ""

    private var openTasks: [Task] {
        allTasks.filter { $0.project?.id == project.id && ($0.status == .todo || $0.status == .started) }
    }
    private var completedTasks: [Task] {
        allTasks.filter { $0.project?.id == project.id && $0.status == .completed }
    }
    private var sortedMeetings: [Minutes] {
        project.meetings.sorted { $0.meetingAt > $1.meetingAt }
    }
    private var projectNotes: [Note] {
        allNotes.filter { $0.project?.id == project.id }
    }

    var body: some View {
        if asSheet {
            NavigationStack { coreContent }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 520)
            #endif
        } else {
            coreContent
        }
    }

    private var coreContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pinned header + action bar (like the diary and meeting-minutes pages); sections scroll below.
            header
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)
            DayActionBar(items: projectActionItems)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("Open Tasks (\(openTasks.count))") { openTasksContent }
                    section("Meetings (\(project.meetings.count))") { meetingsContent }
                    section("Documents (\(project.documents.count))") { documentsContent }
                    if !project.subprojects.isEmpty {
                        section("Subprojects (\(project.subprojects.count))") { subprojectsContent }
                    }
                    if !projectNotes.isEmpty {
                        section("Notes (\(projectNotes.count))") { notesContent }
                    }
                    if !completedTasks.isEmpty { completedTasksSection }
                }
                .padding(.bottom, 28)
            }
        }
        .background(AppTheme.background)
        .navigationTitle(project.name)
        .onAppear { tagsText = project.tags.joined(separator: ", ") }
        .toolbar {
            if asSheet {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheet(isPresented: $showingAddMinutes) { MinutesEditorSheet(minutes: nil, project: project) }
        .sheet(isPresented: $addingSubproject) {
            ProjectEditorSheet(project: nil, defaultParent: project,
                               onCreated: { workspace.openInNewTab(.project($0.persistentModelID)) })
        }
        .sheet(item: $editingDocument) { DocumentEditorSheet(document: $0, requireAttachment: true) }
        .sheet(item: $editingTask) { t in TaskEditorSheet(task: t, defaultDate: Date()) }
        .sheet(item: $editingNote) { n in NoteEditorSheet(note: n) }
    }

    private var projectActionItems: [DayActionItem] {
        [
            DayActionItem(id: "meeting", systemName: "calendar.badge.plus",
                          color: AppTheme.project, tooltip: "Add meeting") { showingAddMinutes = true },
            DayActionItem(id: "document", systemName: "doc.badge.plus",
                          color: AppTheme.duration, tooltip: "Add document") { addDocument() },
            DayActionItem(id: "subproject", systemName: "folder.badge.plus",
                          color: AppTheme.project, tooltip: "Add subproject") { addingSubproject = true },
        ]
    }

    // A titled section: an app-style DaySectionHeader (uppercase, optional "+") + padded content.
    @ViewBuilder
    private func section<Content: View>(_ title: String, onAdd: (() -> Void)? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        DaySectionHeader(title: title, onAdd: onAdd)
        VStack(alignment: .leading, spacing: 4) { content() }
            .padding(.horizontal)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text).foregroundStyle(AppTheme.mutedText).font(.callout).padding(.vertical, 2)
    }

    private func meetingCaption(_ meeting: Minutes) -> String {
        let date = meeting.meetingAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        let n = meeting.attendees.count
        return n > 0 ? "\(date) · \(n) attendee\(n == 1 ? "" : "s")" : date
    }

    private func documentCaption(_ doc: Document) -> String {
        let n = doc.attachments.count
        let files = "\(n) file\(n == 1 ? "" : "s")"
        if let desc = doc.documentDescription, !desc.isEmpty { return "\(files) · \(desc)" }
        return files
    }

    // MARK: - Header (title + status + a minutes-style metadata card)

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(project.name)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.text)
            statusControl
            metadataCard
        }
    }

    // Inline-editable metadata (mirrors MinutesDetailView.metadataHeader): every project-table field is
    // editable in place via a bound TextField / FuzzyPickerField — no separate editor needed.
    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            metaRow("Description") {
                TextField("Description", text: descriptionBinding, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
            }
            metaRow("Stream") {
                TextField("Stream", text: streamBinding)
                    .textFieldStyle(.roundedBorder)
            }
            metaRow("Parent") {
                FuzzyPickerField(
                    allItems: allProjects.filter { $0.id != project.id },
                    selectedItem: parentBinding,
                    label: { $0.name },
                    chipColor: AppTheme.project,
                    tapArea: true,
                    emptyLabel: "None — tap to choose"
                )
            }
            metaRow("Dev Team") { teamField(dev: true) }
            metaRow("Sci Team") { teamField(dev: false) }
            metaRow("Tags") {
                TextField("Comma-separated tags", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: tagsText) { _, newValue in
                        project.tags = newValue.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        project.updatedAt = Date()
                    }
            }
            if let last = project.meetings.map(\.meetingAt).max() {
                metaRow("Last Meeting") {
                    Text(last, format: .dateTime.day().month(.abbreviated).year())
                        .foregroundStyle(AppTheme.mutedText)
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

    // Team picker + a Lead sub-picker (lead required when the team is non-empty — auto-set to the first
    // member if none is chosen; cleared/reassigned when the current lead leaves the team).
    private func teamField(dev: Bool) -> some View {
        let team = dev ? project.devTeam : project.sciTeam
        let peopleBinding = Binding<[Person]>(
            get: { dev ? project.devTeam : project.sciTeam },
            set: { setTeam(dev: dev, people: $0) }
        )
        let leadBinding = Binding<Person?>(
            get: { dev ? project.devLead : project.sciLead },
            set: { newLead in
                if dev { project.devLead = newLead } else { project.sciLead = newLead }
                project.updatedAt = Date()
            }
        )
        return VStack(alignment: .leading, spacing: 6) {
            FuzzyPickerField(
                allItems: allPeople,
                selected: peopleBinding,
                label: \.name,
                chipColor: AppTheme.person,
                onCreateItem: { makePerson($0) },
                tapArea: true,
                emptyLabel: "None — tap to add"
            )
            if !team.isEmpty {
                HStack(spacing: 6) {
                    Text("Lead").font(.caption2).foregroundStyle(.secondary)
                    FuzzyPickerField(
                        allItems: team,
                        selectedItem: leadBinding,
                        label: { $0.name },
                        chipColor: AppTheme.followUp,
                        tapArea: true,
                        emptyLabel: "Choose lead"
                    )
                }
            }
        }
    }

    private func setTeam(dev: Bool, people: [Person]) {
        let ids = Set(people.map(\.id))
        if dev {
            project.devTeam = people
            if let lead = project.devLead, !ids.contains(lead.id) { project.devLead = nil }
            if project.devLead == nil { project.devLead = people.first }
        } else {
            project.sciTeam = people
            if let lead = project.sciLead, !ids.contains(lead.id) { project.sciLead = nil }
            if project.sciLead == nil { project.sciLead = people.first }
        }
        project.updatedAt = Date()
    }

    private var descriptionBinding: Binding<String> {
        Binding(get: { project.projectDescription ?? "" },
                set: { project.projectDescription = $0.isEmpty ? nil : $0; project.updatedAt = Date() })
    }
    private var streamBinding: Binding<String> {
        Binding(get: { project.stream ?? "" },
                set: { project.stream = $0.isEmpty ? nil : $0; project.updatedAt = Date() })
    }
    private var parentBinding: Binding<Project?> {
        Binding(get: { project.parent },
                set: { project.parent = $0; project.updatedAt = Date() })
    }

    private func makePerson(_ name: String) -> Person? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let person = Person(name: trimmed)
        modelContext.insert(person)
        return person
    }

    // Active/Completed status. Enforces the hierarchy invariant (see ProjectStatusRules): a project can
    // only be completed once its subprojects are, and can only be reactivated once its parent is active.
    private var statusControl: some View {
        let canComplete = ProjectStatusRules.canComplete(subprojectsCompleted: project.subprojects.map(\.isCompleted))
        let canReactivate = ProjectStatusRules.canReactivate(parentCompleted: project.parent?.isCompleted)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Chip(label: project.isCompleted ? "Completed" : "Active",
                     color: project.isCompleted ? AppTheme.mutedText : AppTheme.today)
                if project.isCompleted {
                    Button("Reactivate") { setCompleted(false) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(!canReactivate)
                } else {
                    Button("Mark Completed") { setCompleted(true) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(!canComplete)
                }
            }
            if !project.isCompleted && !canComplete {
                Text("Complete all subprojects before marking this project completed.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if project.isCompleted && !canReactivate {
                Text("Reactivate the parent project\(project.parent.map { " (\($0.name))" } ?? "") before reactivating this one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func setCompleted(_ completed: Bool) {
        project.isCompleted = completed
        project.updatedAt = Date()
    }

    // MARK: - Section content

    @ViewBuilder private var openTasksContent: some View {
        if openTasks.isEmpty {
            emptyLine("No open tasks.")
        } else {
            ForEach(openTasks) { task in TaskRowView(task: task, onEdit: { editingTask = task }) }
        }
    }

    @ViewBuilder private var meetingsContent: some View {
        if sortedMeetings.isEmpty {
            emptyLine("No meetings.")
        } else {
            ForEach(sortedMeetings) { meeting in
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

    @ViewBuilder private var documentsContent: some View {
        if project.documents.isEmpty {
            emptyLine("No documents.")
        } else {
            ForEach(project.documents) { doc in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "doc")
                        .foregroundStyle(AppTheme.duration).font(.system(size: 12))
                        .frame(width: 18).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(doc.summary?.isEmpty == false ? doc.summary! : "Untitled document")
                            .foregroundStyle(AppTheme.text).lineLimit(1)
                        Text(documentCaption(doc))
                            .font(.caption).foregroundStyle(AppTheme.mutedText).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { workspace.focusOrOpen(.document(doc.persistentModelID)) }
            }
        }
    }

    @ViewBuilder private var subprojectsContent: some View {
        ForEach(project.subprojects.sorted { $0.name < $1.name }) { sub in
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(AppTheme.project).font(.system(size: 12)).frame(width: 18)
                Text(sub.name).foregroundStyle(AppTheme.text).lineLimit(1)
                if sub.isCompleted { Chip(label: "Completed", color: AppTheme.mutedText) }
                Spacer()
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { workspace.focusOrOpen(.project(sub.persistentModelID)) }
        }
    }

    @ViewBuilder private var notesContent: some View {
        ForEach(projectNotes) { note in
            VStack(alignment: .leading, spacing: 2) {
                Text(note.content.isEmpty ? "Empty note" : note.content)
                    .lineLimit(3)
                    .foregroundStyle(note.content.isEmpty ? AppTheme.mutedText : AppTheme.text)
                if !note.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(note.tags, id: \.self) { Chip(label: $0, color: AppTheme.tag) }
                    }
                }
                Text(note.createdAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { editingNote = note }
        }
    }

    // Completed tasks are important but rarely needed — collapsed by default.
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

    private func addDocument() {
        let doc = Document()
        doc.projects = [project]
        modelContext.insert(doc)
        editingDocument = doc
    }
}
