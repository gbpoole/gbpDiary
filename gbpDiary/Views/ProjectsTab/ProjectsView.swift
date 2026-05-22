import SwiftUI
import SwiftData

struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var selectedProject: Project?
    @State private var showingAddProject = false

    private var rootProjects: [Project] {
        projects.filter { $0.parent == nil && !$0.isCompleted }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedProject) {
                ForEach(rootProjects) { project in
                    ProjectRowView(project: project, selectedProject: $selectedProject)
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem {
                    Button { showingAddProject = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        } detail: {
            if let project = selectedProject {
                ProjectDetailView(project: project)
            } else {
                ContentUnavailableView("Select a Project",
                                       systemImage: "folder",
                                       description: Text("Choose a project from the sidebar."))
            }
        }
        .sheet(isPresented: $showingAddProject) {
            ProjectEditorSheet(project: nil)
        }
    }
}

private struct ProjectRowView: View {
    let project: Project
    @Binding var selectedProject: Project?

    var body: some View {
        DisclosureGroup {
            ForEach(project.subprojects.filter { !$0.isCompleted }) { sub in
                Text(sub.name)
                    .onTapGesture { selectedProject = sub }
            }
        } label: {
            HStack {
                Text(project.name)
                Spacer()
                if !project.meetings.isEmpty {
                    Text(project.meetings.sorted { $0.meetingAt > $1.meetingAt }.first!.meetingAt,
                         format: .dateTime.day().month())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onTapGesture { selectedProject = project }
    }
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
