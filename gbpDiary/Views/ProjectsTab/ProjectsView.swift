import SwiftUI
import SwiftData

struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var showingAddProject = false
    // @Model exposes `id: UUID` (its @Attribute), so the Table's selection is keyed by UUID.
    @State private var selection: Set<UUID> = []
    @State private var stashedSelection: Set<UUID> = []
    @State private var confirmingBulkDelete = false

    // Filter/search/sort live on the active tab (persisted + remembered across tab switches).
    private var filter: ListPageFilter { workspace.active.pageFilter(for: .projects) }
    private static let sortColumns: [SortColumn<Project>] = [
        SortColumn("name", \.nameKey), SortColumn("stream", \.streamKey),
        SortColumn("devTeam", \.devTeamKey), SortColumn("sciTeam", \.sciTeamKey),
        SortColumn("subprojects", \.subprojectCount), SortColumn("lastMeeting", \.lastMeetingAt),
    ]
    private var sortOrderBinding: Binding<[KeyPathComparator<Project>]> {
        let f = filter
        return Binding(
            get: { TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "name") },
            set: { if let d = TableSortPersistence.descriptor(for: $0, columns: Self.sortColumns) { f.sortColumnID = d.id; f.sortAscending = d.ascending } }
        )
    }

    private var projectFilters: [PickerFilter<Project>] {
        let statusGroup = [
            PickerFilter<Project>(id: "status.active", label: "Active", chipColor: AppTheme.accent, group: "Status") { !$0.isCompleted },
            PickerFilter<Project>(id: "status.completed", label: "Completed", chipColor: AppTheme.accent, group: "Status") { $0.isCompleted },
        ]
        let streams = Set(projects.compactMap(\.stream)).sorted()
        let streamGroup = streams.map { stream in
            PickerFilter<Project>(id: "stream.\(stream)", label: stream, chipColor: AppTheme.tag, group: "Stream") {
                $0.stream == stream
            }
        }
        return statusGroup + streamGroup
    }

    private var rows: [Project] {
        let f = filter
        let matched = FilterEngine.apply(projects, filters: projectFilters, activeIds: f.activeFilterIds)
        let query = f.searchText.trimmingCharacters(in: .whitespaces)
        let searched = query.isEmpty ? matched : matched.filter { FuzzyMatch.matches(query, in: searchHaystack($0)) }
        return searched.sorted(using: TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "name"))
    }

    private func searchHaystack(_ p: Project) -> String {
        [p.name, p.stream, p.devTeamKey, p.sciTeamKey, p.tags.joined(separator: " ")]
            .compactMap { $0 }.joined(separator: " ")
    }

    private var selectedProjects: [Project] {
        projects.filter { selection.contains($0.id) }
    }

    private func clearSelection() { selection.removeAll(); stashedSelection.removeAll() }

    private func bulkDelete() {
        for p in selectedProjects {
            workspace.closeEntity(p.persistentModelID)
            modelContext.delete(p)
        }
        clearSelection()
    }

    var body: some View {
        @Bindable var f = filter
        return VStack(spacing: 0) {
            ListToolbar(
                searchText: $f.searchText,
                searchPrompt: "Search projects…",
                filters: projectFilters,
                activeFilterIds: $f.activeFilterIds,
                onClearAll: { f.activeFilterIds = [] }
            )
            BulkActionBar(count: selection.count, onClear: { clearSelection() }) {
                Button("Delete", role: .destructive) { confirmingBulkDelete = true }
            }
            Divider()
            projectTable
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem {
                Button { showingAddProject = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddProject) { ProjectEditorSheet(project: nil) }
        .alert("Delete \(selection.count) project\(selection.count == 1 ? "" : "s")?", isPresented: $confirmingBulkDelete) {
            Button("Delete", role: .destructive) { bulkDelete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes the selected project\(selection.count == 1 ? "" : "s"). Related items are unlinked, not deleted.") }
        .onChange(of: Set(rows.map(\.id))) { _, visible in
            let result = TableSelectionReconcile.reconcile(selection: selection, stashed: stashedSelection, visible: visible)
            if result.selection != selection { selection = result.selection }
            if result.stashed != stashedSelection { stashedSelection = result.stashed }
        }
    }

    private func open(_ project: Project) { workspace.focusOrOpen(.project(project.persistentModelID)) }

    #if os(macOS)
    private var projectTable: some View {
        Table(rows, selection: $selection, sortOrder: sortOrderBinding) {
            TableColumn("Name", value: \.nameKey) { project in
                Text(project.name)
                    .lineLimit(1)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.text)
            }
            .width(min: 140, ideal: 240)
            TableColumn("Stream", value: \.streamKey) { project in
                Text(project.stream ?? "")
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 100)
            TableColumn("Dev Team", value: \.devTeamKey) { project in
                Text(Project.teamNames(lead: project.devLead, team: project.devTeam).joined(separator: ", "))
                    .foregroundStyle(AppTheme.person)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 140)
            TableColumn("Sci Team", value: \.sciTeamKey) { project in
                Text(Project.teamNames(lead: project.sciLead, team: project.sciTeam).joined(separator: ", "))
                    .foregroundStyle(AppTheme.person)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 140)
            TableColumn("Subprojects", value: \.subprojectCount) { project in
                Text("\(project.subprojects.count)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Last Meeting", value: \.lastMeetingAt) { project in
                if let latest = project.meetings.max(by: { $0.meetingAt < $1.meetingAt }) {
                    Text(latest.meetingAt, format: .dateTime.day().month(.abbreviated).year())
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            .width(min: 90, ideal: 110)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .onTableRowDoubleClick { open(rows[$0]) }
    }
    #else
    private var projectTable: some View {
        List(rows) { project in
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                if let stream = project.stream {
                    Text(stream).font(.caption).foregroundStyle(.secondary)
                }
            }
            .onTapGesture { open(project) }
        }
    }
    #endif
}

struct ProjectEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceModel.self) private var workspace

    let project: Project?

    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var name = ""
    @State private var description = ""
    @State private var stream = ""
    @State private var tagsText = ""
    @State private var selectedParent: Project?
    @State private var selectedDevPeople: [Person] = []
    @State private var devLeadId: UUID? = nil
    @State private var selectedSciPeople: [Person] = []
    @State private var sciLeadId: UUID? = nil
    @State private var showingDeleteConfirm = false

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if !selectedDevPeople.isEmpty && devLeadId == nil { return false }
        if !selectedSciPeople.isEmpty && sciLeadId == nil { return false }
        return true
    }

    private var institutionFilters: [PickerFilter<Person>] {
        var seen = Set<String>()
        return allPeople
            .compactMap(\.institution)
            .filter { seen.insert($0.id.uuidString).inserted }
            .sorted { $0.name < $1.name }
            .map { inst in
                PickerFilter(id: inst.id.uuidString, label: inst.name, chipColor: AppTheme.institution, group: "Institution") {
                    $0.institution?.id == inst.id
                }
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Name") {
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    }
                    GroupBox("Description") {
                        TextField("Description", text: $description, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    }
                    GroupBox("Stream") {
                        TextField("Stream", text: $stream)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    }
                    GroupBox("Tags") {
                        TextField("Comma-separated tags", text: $tagsText)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    }
                    GroupBox("Parent project") {
                        FuzzyPickerField(
                            allItems: allProjects.filter { $0.id != project?.id },
                            selectedItem: $selectedParent,
                            label: { $0.name },
                            chipColor: AppTheme.project,
                            tapArea: true,
                            emptyLabel: "None — tap to choose"
                        )
                    }
                    GroupBox("Dev Team") { teamSection(dev: true) }
                    GroupBox("Sci Team") { teamSection(dev: false) }
                }
                .padding()
            }
            .navigationTitle(project == nil ? "New Project" : "Edit Project")
            .toolbar {
                if project != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete") { showingDeleteConfirm = true }
                            .buttonStyle(.borderedProminent).tint(.red)
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(project == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .alert("Delete Project?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteProject() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the project. Its tasks, meetings, documents, and notes are kept but no longer reference it.")
            }
        }
        .onAppear {
            if let p = project {
                name = p.name
                description = p.projectDescription ?? ""
                stream = p.stream ?? ""
                tagsText = p.tags.joined(separator: ", ")
                selectedParent = p.parent
                selectedDevPeople = p.devTeam
                devLeadId = p.devLead?.id
                selectedSciPeople = p.sciTeam
                sciLeadId = p.sciLead?.id
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
        #endif
    }

    @ViewBuilder private func teamSection(dev: Bool) -> some View {
        let members = dev ? selectedDevPeople : selectedSciPeople
        let peopleBinding = Binding<[Person]>(
            get: { dev ? selectedDevPeople : selectedSciPeople },
            set: { newPeople in
                let removed = Set(members.map(\.id)).subtracting(newPeople.map(\.id))
                if dev {
                    if let leadId = devLeadId, removed.contains(leadId) { devLeadId = nil }
                    selectedDevPeople = newPeople
                } else {
                    if let leadId = sciLeadId, removed.contains(leadId) { sciLeadId = nil }
                    selectedSciPeople = newPeople
                }
            }
        )
        let leadBinding = Binding<Person?>(
            get: { members.first { $0.id == (dev ? devLeadId : sciLeadId) } },
            set: { if dev { devLeadId = $0?.id } else { sciLeadId = $0?.id } }
        )
        VStack(alignment: .leading, spacing: 8) {
            FuzzyPickerField(
                allItems: allPeople,
                selected: peopleBinding,
                label: \.name,
                chipColor: AppTheme.person,
                onCreateItem: { makePerson($0) },
                filters: institutionFilters
            )
            if !members.isEmpty {
                HStack(spacing: 8) {
                    Text("Lead").font(.caption).foregroundStyle(.secondary)
                    FuzzyPickerField(
                        allItems: members,
                        selectedItem: leadBinding,
                        label: { $0.name },
                        chipColor: AppTheme.person,
                        tapArea: true,
                        emptyLabel: "Choose lead"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Create a new Person on the fly while picking team members (auto-added to the selection).
    private func makePerson(_ personName: String) -> Person? {
        let trimmed = personName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let person = Person(name: trimmed)
        modelContext.insert(person)
        return person
    }

    private func save() {
        guard canSave else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let parsedTags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let devPeople = selectedDevPeople
        let sciPeople = selectedSciPeople
        let devLead = allPeople.first { $0.id == devLeadId }
        let sciLead = allPeople.first { $0.id == sciLeadId }
        if let p = project {
            p.name = trimmed
            p.projectDescription = description.isEmpty ? nil : description
            p.stream = stream.isEmpty ? nil : stream
            p.tags = parsedTags
            p.parent = selectedParent
            p.devTeam = devPeople
            p.devLead = devLead
            p.sciTeam = sciPeople
            p.sciLead = sciLead
            p.updatedAt = Date()
        } else {
            let p = Project(name: trimmed)
            p.projectDescription = description.isEmpty ? nil : description
            p.stream = stream.isEmpty ? nil : stream
            p.tags = parsedTags
            p.parent = selectedParent
            p.devTeam = devPeople
            p.devLead = devLead
            p.sciTeam = sciPeople
            p.sciLead = sciLead
            modelContext.insert(p)
        }
        dismiss()
    }

    private func deleteProject() {
        guard let p = project else { return }
        workspace.closeEntity(p.persistentModelID)
        modelContext.delete(p)
        dismiss()
    }
}
