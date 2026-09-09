import SwiftUI
import SwiftData

struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \Institution.name) private var institutions: [Institution]
    @Query(sort: \Project.name) private var projects: [Project]

    @Environment(WorkspaceModel.self) private var workspace

    @State private var showingAddPerson = false
    // @Model exposes `id: UUID` (its @Attribute), so the Table's selection is keyed by UUID.
    @State private var selection: Set<UUID> = []
    @State private var stashedSelection: Set<UUID> = []
    @State private var confirmingBulkDelete = false

    // Filter/search/sort live on the active tab (persisted + remembered across tab switches).
    private var filter: ListPageFilter { workspace.active.pageFilter(for: .people) }
    private static let sortColumns: [SortColumn<Person>] = [
        SortColumn("name", \.nameKey), SortColumn("email", \.emailKey),
        SortColumn("institution", \.institutionKey), SortColumn("tags", \.tagsKey),
        SortColumn("projects", \.projectCount),
    ]
    private var sortOrderBinding: Binding<[KeyPathComparator<Person>]> {
        let f = filter
        return Binding(
            get: { TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "name") },
            set: { if let d = TableSortPersistence.descriptor(for: $0, columns: Self.sortColumns) { f.sortColumnID = d.id; f.sortAscending = d.ascending } }
        )
    }

    private var personFilters: [PickerFilter<Person>] {
        let institutionGroup = institutions.map { inst in
            PickerFilter<Person>(id: "institution.\(inst.id)", label: inst.name, chipColor: AppTheme.institution, group: "Institution") {
                $0.institution?.id == inst.id
            }
        }
        // Project membership: on the project's dev or sci team.
        let projectGroup = projects.map { project in
            PickerFilter<Person>(id: "project.\(project.id)", label: project.name, chipColor: AppTheme.project, group: "Project") { person in
                person.devProjects.contains { $0.id == project.id } || person.sciProjects.contains { $0.id == project.id }
            }
        }
        let allTags = Set(people.flatMap(\.tags)).sorted()
        let tagGroup = allTags.map { tag in
            PickerFilter<Person>(id: "tag.\(tag)", label: tag, chipColor: AppTheme.tag, group: "Tag") {
                $0.tags.contains(tag)
            }
        }
        return institutionGroup + projectGroup + tagGroup
    }

    private var rows: [Person] {
        let f = filter
        let matched = FilterEngine.apply(people, filters: personFilters, activeIds: f.activeFilterIds)
        let query = f.searchText.trimmingCharacters(in: .whitespaces)
        let searched = query.isEmpty ? matched : matched.filter {
            PersonSearch.matches(query: query, name: $0.name, emails: $0.emails,
                                 institution: $0.institution?.name, tags: $0.tags)
        }
        return searched.sorted(using: TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "name"))
    }

    private var selectedPeople: [Person] {
        people.filter { selection.contains($0.id) }
    }

    private func clearSelection() { selection.removeAll(); stashedSelection.removeAll() }

    private func bulkDelete() {
        for p in selectedPeople {
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
                searchPrompt: "Search people…",
                filters: personFilters,
                activeFilterIds: $f.activeFilterIds,
                onClearAll: { f.activeFilterIds = [] }
            )
            BulkActionBar(count: selection.count, onClear: { clearSelection() }) {
                Button("Delete", role: .destructive) { confirmingBulkDelete = true }
            }
            Divider()
            peopleTable
        }
        .navigationTitle("People")
        .toolbar {
            ToolbarItem {
                Button { showingAddPerson = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPerson) { PersonEditorSheet(person: nil) }
        .alert("Delete \(selection.count) \(selection.count == 1 ? "person" : "people")?", isPresented: $confirmingBulkDelete) {
            Button("Delete", role: .destructive) { bulkDelete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes the selected \(selection.count == 1 ? "person" : "people"). Related items are unlinked, not deleted.") }
        .onChange(of: Set(rows.map(\.id))) { _, visible in
            let result = TableSelectionReconcile.reconcile(selection: selection, stashed: stashedSelection, visible: visible)
            if result.selection != selection { selection = result.selection }
            if result.stashed != stashedSelection { stashedSelection = result.stashed }
        }
    }

    // Row-tap rule: Person is now a rich entity — open its detail page in a workspace tab
    // (reusing an already-open tab for that person). New people are created via the "+" toolbar button.
    private func open(_ person: Person) { workspace.focusOrOpen(.person(person.persistentModelID)) }

    #if os(macOS)
    private var peopleTable: some View {
        Table(rows, selection: $selection, sortOrder: sortOrderBinding) {
            TableColumn("Name", value: \.nameKey) { person in
                Text(person.name)
                    .lineLimit(1)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.text)
            }
            .width(min: 140, ideal: 220)
            TableColumn("Email", value: \.emailKey) { person in
                Text(person.primaryEmail ?? "")
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 180)
            TableColumn("Institution", value: \.institutionKey) { person in
                Text(person.institution?.name ?? "")
                    .foregroundStyle(AppTheme.institution)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 140)
            TableColumn("Tags", value: \.tagsKey) { person in
                Text(person.tags.joined(separator: ", "))
                    .foregroundStyle(AppTheme.tag)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 160)
            TableColumn("Projects", value: \.projectCount) { person in
                Text("\(person.projectCount)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(min: 60, ideal: 70)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .onTableRowDoubleClick { open(rows[$0]) }
    }
    #else
    private var peopleTable: some View {
        List(rows) { person in
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                if let inst = person.institution {
                    Text(inst.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            .onTapGesture { open(person) }
        }
    }
    #endif
}

struct PersonEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceModel.self) private var workspace

    let person: Person?

    @Query(sort: \Institution.name) private var institutions: [Institution]

    @State private var name = ""
    @State private var emails: [String] = []
    @State private var tagsText = ""
    @State private var selectedInstitution: Institution?
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Name") {
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    }
                    GroupBox("Emails") {
                        EmailListEditor(emails: $emails)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Institution") {
                        FuzzyPickerField(
                            allItems: institutions,
                            selectedItem: $selectedInstitution,
                            label: { $0.name },
                            chipColor: AppTheme.institution,
                            onCreateItem: { makeInstitution($0) },
                            tapArea: true,
                            emptyLabel: "None — tap to choose or add"
                        )
                    }
                    GroupBox("Tags") {
                        TextField("Comma-separated tags", text: $tagsText)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .navigationTitle(person == nil ? "New Person" : "Edit Person")
            .toolbar {
                if person != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete") { showingDeleteConfirm = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(person == nil ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Delete Person?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { deletePerson() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the person. Their tasks, meetings, and projects are kept but no longer reference them.")
            }
        }
        .onAppear {
            if let p = person {
                name = p.name
                emails = p.emails
                tagsText = p.tags.joined(separator: ", ")
                selectedInstitution = p.institution
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    // Create an Institution on the fly while picking one (auto-selected).
    private func makeInstitution(_ instName: String) -> Institution? {
        let trimmed = instName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let inst = Institution(name: trimmed)
        modelContext.insert(inst)
        return inst
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let parsedTags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let p = person {
            p.name = trimmed
            p.emails = emails
            p.institution = selectedInstitution
            p.tags = parsedTags
            p.updatedAt = Date()
        } else {
            let p = Person(name: trimmed)
            p.emails = emails
            p.institution = selectedInstitution
            p.tags = parsedTags
            modelContext.insert(p)
        }
        dismiss()
    }

    private func deletePerson() {
        guard let p = person else { return }
        workspace.closeEntity(p.persistentModelID)   // close any open tab referencing this person
        modelContext.delete(p)
        dismiss()
    }
}
