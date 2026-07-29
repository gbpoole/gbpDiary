import SwiftUI
import SwiftData

struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \Institution.name) private var institutions: [Institution]

    @State private var selectedPerson: Person?
    @State private var showingAddPerson = false
    @State private var activeFilterIds: Set<String> = []

    private var personFilters: [PickerFilter<Person>] {
        let institutionGroup = institutions.map { inst in
            PickerFilter<Person>(id: "institution.\(inst.id)", label: inst.name, chipColor: AppTheme.institution, group: "Institution") {
                $0.institution?.id == inst.id
            }
        }
        let allTags = Set(people.flatMap(\.tags)).sorted()
        let tagGroup = allTags.map { tag in
            PickerFilter<Person>(id: "tag.\(tag)", label: tag, chipColor: AppTheme.tag, group: "Tag") {
                $0.tags.contains(tag)
            }
        }
        return institutionGroup + tagGroup
    }

    private var filteredPeople: [Person] {
        FilterEngine.apply(people, filters: personFilters, activeIds: activeFilterIds)
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(
                filters: personFilters,
                activeFilterIds: $activeFilterIds,
                onClearAll: { activeFilterIds = [] }
            )
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
        .sheet(item: $selectedPerson) { PersonEditorSheet(person: $0) }
        .sheet(isPresented: $showingAddPerson) { PersonEditorSheet(person: nil) }
    }

    #if os(macOS)
    private var peopleTable: some View {
        Table(filteredPeople) {
            TableColumn("Name") { person in
                Text(person.name)
                    .lineLimit(1)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.text)
                    .onTapGesture { selectedPerson = person }
            }
            TableColumn("Email") { person in
                Text(person.primaryEmail ?? "")
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
            .width(180)
            TableColumn("Institution") { person in
                Text(person.institution?.name ?? "")
                    .foregroundStyle(AppTheme.institution)
                    .lineLimit(1)
            }
            .width(140)
            TableColumn("Tags") { person in
                Text(person.tags.joined(separator: ", "))
                    .foregroundStyle(AppTheme.tag)
                    .lineLimit(1)
            }
            .width(160)
            TableColumn("Projects") { person in
                Text("\(person.devProjects.count + person.sciProjects.count)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(70)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
    }
    #else
    private var peopleTable: some View {
        List(filteredPeople) { person in
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                if let inst = person.institution {
                    Text(inst.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            .onTapGesture { selectedPerson = person }
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
