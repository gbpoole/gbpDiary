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
        .sheet(item: $selectedPerson) { PersonDetailView(person: $0, asSheet: true) }
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
                Text(person.email ?? "")
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

    let person: Person?

    @Query(sort: \Institution.name) private var institutions: [Institution]

    @State private var name = ""
    @State private var email = ""
    @State private var tagsText = ""
    @State private var selectedInstitution: Institution?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Email (optional)", text: $email)
                    .textContentType(.emailAddress)
                Picker("Institution", selection: $selectedInstitution) {
                    Text("None").tag(Optional<Institution>.none)
                    ForEach(institutions) { inst in
                        Text(inst.name).tag(Optional(inst))
                    }
                }
                Section("Tags") {
                    TextField("Comma-separated tags", text: $tagsText)
                }
            }
            .navigationTitle(person == nil ? "New Person" : "Edit Person")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(person == nil ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if let p = person {
                name = p.name
                email = p.email ?? ""
                tagsText = p.tags.joined(separator: ", ")
                selectedInstitution = p.institution
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 280)
        #endif
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let parsedTags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let p = person {
            p.name = trimmed
            p.email = email.isEmpty ? nil : email
            p.institution = selectedInstitution
            p.tags = parsedTags
            p.updatedAt = Date()
        } else {
            let p = Person(name: trimmed)
            p.email = email.isEmpty ? nil : email
            p.institution = selectedInstitution
            p.tags = parsedTags
            modelContext.insert(p)
        }
        dismiss()
    }
}
