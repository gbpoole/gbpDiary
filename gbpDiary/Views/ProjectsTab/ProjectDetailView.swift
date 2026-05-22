import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    @Bindable var project: Project

    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Environment(\.modelContext) private var modelContext

    @State private var showingEditProject = false
    @State private var showingAddMinutes = false
    @State private var showingAddDocument = false
    @State private var selectedMinutes: Minutes?
    @State private var editingTask: Task?

    private var openTasks: [Task] {
        allTasks.filter { $0.project?.id == project.id && $0.status == .open }
    }

    private var completedTasks: [Task] {
        allTasks.filter { $0.project?.id == project.id && $0.status == .completed }
    }

    private var sortedMeetings: [Minutes] {
        project.meetings.sorted { $0.meetingAt > $1.meetingAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !project.subprojects.isEmpty { subprojectsSection }
                openTasksSection
                if !completedTasks.isEmpty { completedTasksSection }
                meetingsSection
                documentsSection
            }
            .padding()
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem {
                Button { showingEditProject = true } label: { Image(systemName: "pencil") }
            }
        }
        .sheet(isPresented: $showingEditProject) { ProjectEditorSheet(project: project) }
        .sheet(isPresented: $showingAddMinutes) { MinutesEditorSheet(minutes: nil, project: project) }
        .sheet(item: $selectedMinutes) { m in MinutesDetailView(minutes: m) }
        .sheet(item: $editingTask) { t in TaskEditorSheet(task: t, defaultDate: Date()) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let desc = project.projectDescription {
                Text(desc).foregroundStyle(.secondary)
            }
            if let type = project.projectType {
                Text(type).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var subprojectsSection: some View {
        GroupBox("Subprojects (\(project.subprojects.count))") {
            ForEach(project.subprojects) { sub in
                Text(sub.name).padding(.vertical, 2)
            }
        }
    }

    private var openTasksSection: some View {
        GroupBox("Open Tasks (\(openTasks.count))") {
            if openTasks.isEmpty {
                Text("No open tasks.").foregroundStyle(.secondary)
            } else {
                ForEach(openTasks) { task in
                    TaskRowView(task: task, onEdit: { editingTask = task })
                }
            }
        }
    }

    private var completedTasksSection: some View {
        GroupBox("Completed Tasks (\(completedTasks.count))") {
            ForEach(completedTasks) { task in
                TaskRowView(task: task, onEdit: { editingTask = task })
            }
        }
    }

    private var meetingsSection: some View {
        GroupBox {
            if sortedMeetings.isEmpty {
                Text("No meetings.").foregroundStyle(.secondary)
            } else {
                ForEach(sortedMeetings) { m in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.meetingAt, format: .dateTime.day().month(.wide).year())
                                .font(.subheadline.bold())
                            if let s = m.summary { Text(s).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button { selectedMinutes = m } label: {
                            Image(systemName: "doc.text")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
        } label: {
            HStack {
                Text("Meetings (\(project.meetings.count))")
                Spacer()
                Button { showingAddMinutes = true } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.plain)
            }
        }
    }

    private var documentsSection: some View {
        GroupBox("Documents (\(project.documents.count))") {
            if project.documents.isEmpty {
                Text("No documents.").foregroundStyle(.secondary)
            } else {
                ForEach(project.documents) { doc in
                    Text(doc.documentDescription ?? "Untitled document")
                        .padding(.vertical, 2)
                }
            }
            Button { showingAddDocument = true } label: {
                Label("Add Document", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(.top, 4)
        }
    }
}
