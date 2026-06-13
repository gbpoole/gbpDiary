import SwiftUI
import SwiftData

struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var selectedProject: Project?
    @State private var showingAddProject = false
    @State private var showCompleted = false

    private var filteredProjects: [Project] {
        projects.filter { showCompleted || !$0.isCompleted }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
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
        .sheet(item: $selectedProject) { ProjectDetailView(project: $0, asSheet: true) }
        .sheet(isPresented: $showingAddProject) { ProjectEditorSheet(project: nil) }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Toggle("Show Completed", isOn: $showCompleted)
                .toggleStyle(.checkbox)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    #if os(macOS)
    private var projectTable: some View {
        Table(filteredProjects) {
            TableColumn("Name") { project in
                Text(project.name)
                    .lineLimit(1)
                    .onTapGesture { selectedProject = project }
            }
            TableColumn("Stream") { project in
                Text(project.stream ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(90)
            TableColumn("Dev Team") { project in
                let lead = project.devLead.map { [$0.name] } ?? []
                let others = project.devTeam.filter { $0.id != project.devLead?.id }.map(\.name).sorted()
                Text((lead + others).joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(140)
            TableColumn("Sci Team") { project in
                let lead = project.sciLead.map { [$0.name] } ?? []
                let others = project.sciTeam.filter { $0.id != project.sciLead?.id }.map(\.name).sorted()
                Text((lead + others).joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(140)
            TableColumn("Subprojects") { project in
                Text("\(project.subprojects.count)")
                    .foregroundStyle(.secondary)
            }
            .width(90)
            TableColumn("Last Meeting") { project in
                if let latest = project.meetings.max(by: { $0.meetingAt < $1.meetingAt }) {
                    Text(latest.meetingAt, format: .dateTime.day().month(.abbreviated).year())
                        .foregroundStyle(.secondary)
                }
            }
            .width(110)
        }
    }
    #else
    private var projectTable: some View {
        List(filteredProjects) { project in
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                if let stream = project.stream {
                    Text(stream).font(.caption).foregroundStyle(.secondary)
                }
            }
            .onTapGesture { selectedProject = project }
        }
    }
    #endif
}

struct ProjectEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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

    private var devMembers: [Person] { selectedDevPeople }
    private var sciMembers: [Person] { selectedSciPeople }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if !selectedDevPeople.isEmpty && devLeadId == nil { return false }
        if !selectedSciPeople.isEmpty && sciLeadId == nil { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Description", text: $description, axis: .vertical).lineLimit(3...5)
                TextField("Stream", text: $stream)
                Section("Tags") {
                    TextField("Comma-separated tags", text: $tagsText)
                }
                Picker("Parent project", selection: $selectedParent) {
                    Text("None").tag(Optional<Project>.none)
                    ForEach(allProjects.filter { $0.id != project?.id }) { p in
                        Text(p.name).tag(Optional(p))
                    }
                }

                Section("Dev Team") {
                    FuzzyPickerField(
                        allItems: allPeople,
                        selected: Binding(
                            get: { selectedDevPeople },
                            set: { newPeople in
                                let removed = Set(selectedDevPeople.map(\.id)).subtracting(newPeople.map(\.id))
                                if let leadId = devLeadId, removed.contains(leadId) { devLeadId = nil }
                                selectedDevPeople = newPeople
                            }
                        ),
                        label: \.name,
                        chipColor: AppTheme.person
                    )
                    if !selectedDevPeople.isEmpty {
                        Picker("Dev Lead", selection: $devLeadId) {
                            Text("None").tag(UUID?.none)
                            ForEach(devMembers) { p in
                                Text(p.name).tag(p.id as UUID?)
                            }
                        }
                    }
                }

                Section("Sci Team") {
                    FuzzyPickerField(
                        allItems: allPeople,
                        selected: Binding(
                            get: { selectedSciPeople },
                            set: { newPeople in
                                let removed = Set(selectedSciPeople.map(\.id)).subtracting(newPeople.map(\.id))
                                if let leadId = sciLeadId, removed.contains(leadId) { sciLeadId = nil }
                                selectedSciPeople = newPeople
                            }
                        ),
                        label: \.name,
                        chipColor: AppTheme.person
                    )
                    if !selectedSciPeople.isEmpty {
                        Picker("Sci Lead", selection: $sciLeadId) {
                            Text("None").tag(UUID?.none)
                            ForEach(sciMembers) { p in
                                Text(p.name).tag(p.id as UUID?)
                            }
                        }
                    }
                }
            }
            .navigationTitle(project == nil ? "New Project" : "Edit Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(project == nil ? "Add" : "Save") { save() }
                        .disabled(!canSave)
                }
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
}
