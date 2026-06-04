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
            TableColumn("Type") { project in
                Text(project.projectType ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(100)
            TableColumn("Parent") { project in
                Text(project.parent?.name ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(120)
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
            TableColumn("Created") { project in
                Text(project.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .foregroundStyle(.secondary)
            }
            .width(100)
        }
    }
    #else
    private var projectTable: some View {
        List(filteredProjects) { project in
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                if let type = project.projectType {
                    Text(type).font(.caption).foregroundStyle(.secondary)
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

    @State private var name = ""
    @State private var description = ""
    @State private var projectType = ""
    @State private var selectedParent: Project?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Description", text: $description, axis: .vertical).lineLimit(3...5)
                TextField("Type", text: $projectType)
                Picker("Parent project", selection: $selectedParent) {
                    Text("None").tag(Optional<Project>.none)
                    ForEach(allProjects.filter { $0.id != project?.id }) { p in
                        Text(p.name).tag(Optional(p))
                    }
                }
            }
            .navigationTitle(project == nil ? "New Project" : "Edit Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(project == nil ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if let p = project {
                name = p.name
                description = p.projectDescription ?? ""
                projectType = p.projectType ?? ""
                selectedParent = p.parent
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let p = project {
            p.name = trimmed
            p.projectDescription = description.isEmpty ? nil : description
            p.projectType = projectType.isEmpty ? nil : projectType
            p.parent = selectedParent
            p.updatedAt = Date()
        } else {
            let p = Project(name: trimmed)
            p.projectDescription = description.isEmpty ? nil : description
            p.projectType = projectType.isEmpty ? nil : projectType
            p.parent = selectedParent
            modelContext.insert(p)
        }
        dismiss()
    }
}
