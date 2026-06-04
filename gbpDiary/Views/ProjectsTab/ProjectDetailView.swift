import SwiftUI
import SwiftData

struct ProjectDetailView: View {
    @Bindable var project: Project
    var asSheet: Bool = false

    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditProject = false
    @State private var showingAddMinutes = false
    @State private var showingAddDocument = false
    @State private var selectedMinutes: Minutes?
    @State private var selectedDocument: Document?
    @State private var editingTask: Task?

    private var openTasks: [Task] {
        allTasks.filter { $0.project?.id == project.id && ($0.status == .todo || $0.status == .started) }
    }

    private var completedTasks: [Task] {
        allTasks.filter { $0.project?.id == project.id && $0.status == .completed }
    }

    private var sortedMeetings: [Minutes] {
        project.meetings.sorted { $0.meetingAt > $1.meetingAt }
    }

    var body: some View {
        if asSheet {
            NavigationStack { coreContent }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 500)
            #endif
        } else {
            coreContent
        }
    }

    private var coreContent: some View {
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
            if asSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            ToolbarItem {
                Button { showingEditProject = true } label: { Image(systemName: "pencil") }
            }
        }
        .sheet(isPresented: $showingEditProject) { ProjectEditorSheet(project: project) }
        .sheet(isPresented: $showingAddMinutes) { MinutesEditorSheet(minutes: nil, project: project) }
        .sheet(item: $selectedMinutes) { m in MinutesDetailView(minutes: m, asSheet: true) }
        .sheet(isPresented: $showingAddDocument) { DocumentEditorSheet(document: nil) }
        .sheet(item: $selectedDocument) { doc in DocumentDetailView(document: doc, asSheet: true) }
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
        GroupBox {
            if project.documents.isEmpty {
                Text("No documents.").foregroundStyle(.secondary)
            } else {
                ForEach(project.documents) { doc in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.summary ?? "Untitled document").font(.subheadline)
                            if let desc = doc.documentDescription {
                                Text(desc).foregroundStyle(.secondary).font(.caption).lineLimit(1)
                            }
                        }
                        Spacer()
                        Button { selectedDocument = doc } label: {
                            Image(systemName: "doc.text")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
            Button { showingAddDocument = true } label: {
                Label("Add Document", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(.top, 4)
        } label: {
            Text("Documents (\(project.documents.count))")
        }
    }
}
