import SwiftUI
import SwiftData

struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \Institution.name) private var institutions: [Institution]

    @State private var selectedPerson: Person?
    @State private var showingAddPerson = false
    @State private var showingAddInstitution = false

    private var grouped: [(institution: Institution?, people: [Person])] {
        var result: [(Institution?, [Person])] = []
        let withInst = Dictionary(grouping: people.filter { $0.institution != nil }) { $0.institution! }
        for inst in institutions {
            if let group = withInst[inst] {
                result.append((inst, group.sorted { $0.name < $1.name }))
            }
        }
        let unaffiliated = people.filter { $0.institution == nil }
        if !unaffiliated.isEmpty { result.append((nil, unaffiliated)) }
        return result
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPerson) {
                ForEach(grouped, id: \.institution?.id) { group in
                    Section(group.institution?.name ?? "Unaffiliated") {
                        ForEach(group.people) { person in
                            Text(person.name)
                                .tag(person)
                        }
                    }
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItemGroup {
                    Button { showingAddInstitution = true } label: {
                        Label("Institution", systemImage: "building.2")
                    }
                    Button { showingAddPerson = true } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
        } detail: {
            if let person = selectedPerson {
                PersonDetailView(person: person)
            } else {
                ContentUnavailableView("Select a Person",
                                       systemImage: "person",
                                       description: Text("Choose someone from the list."))
            }
        }
        .sheet(isPresented: $showingAddPerson) { PersonEditorSheet(person: nil) }
        .sheet(isPresented: $showingAddInstitution) { InstitutionEditorSheet(institution: nil) }
    }
}

struct PersonEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let person: Person?

    @Query(sort: \Institution.name) private var institutions: [Institution]

    @State private var name = ""
    @State private var email = ""
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
                selectedInstitution = p.institution
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 260)
        #endif
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let p = person {
            p.name = trimmed
            p.email = email.isEmpty ? nil : email
            p.institution = selectedInstitution
            p.updatedAt = Date()
        } else {
            let p = Person(name: trimmed)
            p.email = email.isEmpty ? nil : email
            p.institution = selectedInstitution
            modelContext.insert(p)
        }
        dismiss()
    }
}

struct InstitutionEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let institution: Institution?
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
            }
            .navigationTitle(institution == nil ? "New Institution" : "Edit Institution")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(institution == nil ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { name = institution?.name ?? "" }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 160)
        #endif
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let inst = institution {
            inst.name = trimmed
            inst.updatedAt = Date()
        } else {
            modelContext.insert(Institution(name: trimmed))
        }
        dismiss()
    }
}
