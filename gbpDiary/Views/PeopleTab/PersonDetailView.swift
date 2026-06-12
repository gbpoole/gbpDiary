import SwiftUI
import SwiftData

struct PersonDetailView: View {
    @Bindable var person: Person
    var asSheet: Bool = false

    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @Query(sort: \Minutes.meetingAt, order: .reverse) private var allMinutes: [Minutes]
    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false
    @State private var editingTask: Task?
    @State private var selectedMinutes: Minutes?

    private var openTasks: [Task] {
        allTasks.filter { $0.assignee?.id == person.id && ($0.status == .todo || $0.status == .started) }
    }

    private var completedTasks: [Task] {
        allTasks.filter { $0.assignee?.id == person.id && $0.status == .completed }
    }

    private var attendedMinutes: [Minutes] {
        allMinutes.filter { $0.attendees.contains(where: { $0.id == person.id }) }
    }

    var body: some View {
        if asSheet {
            NavigationStack { coreContent }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 480)
            #endif
        } else {
            coreContent
        }
    }

    private var coreContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                contactHeader

                GroupBox("Open Tasks (\(openTasks.count))") {
                    if openTasks.isEmpty {
                        Text("No open tasks.").foregroundStyle(.secondary)
                    } else {
                        ForEach(openTasks) { task in
                            TaskRowView(task: task, onEdit: { editingTask = task })
                        }
                    }
                }

                if !completedTasks.isEmpty {
                    GroupBox("Completed Tasks (\(completedTasks.count))") {
                        ForEach(completedTasks.prefix(10)) { task in
                            TaskRowView(task: task, onEdit: { editingTask = task })
                        }
                    }
                }

                if !attendedMinutes.isEmpty {
                    GroupBox("Meetings (\(attendedMinutes.count))") {
                        ForEach(attendedMinutes.prefix(10)) { m in
                            HStack {
                                Text(m.meetingAt, format: .dateTime.day().month(.wide).year())
                                if let s = m.summary { Text("·").foregroundStyle(.tertiary); Text(s).foregroundStyle(.secondary) }
                                Spacer()
                                Button { selectedMinutes = m } label: { Image(systemName: "doc.text") }
                                    .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                GroupBox("Projects") {
                    let allProjects = (person.devProjects + person.sciProjects)
                        .sorted { $0.name < $1.name }
                    if allProjects.isEmpty {
                        Text("No linked projects.").foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(allProjects) { p in
                                Chip(label: p.name, color: AppTheme.project)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(person.name)
        .toolbar {
            if asSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            ToolbarItem { Button { showingEdit = true } label: { Image(systemName: "pencil") } }
        }
        .sheet(isPresented: $showingEdit) { PersonEditorSheet(person: person) }
        .sheet(item: $editingTask) { t in TaskEditorSheet(task: t, defaultDate: Date()) }
        .sheet(item: $selectedMinutes) { m in MinutesDetailView(minutes: m) }
    }

    private var contactHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let inst = person.institution {
                Text(inst.name).foregroundStyle(.secondary)
            }
            if let email = person.email {
                Link(email, destination: URL(string: "mailto:\(email)")!)
                    .font(.subheadline)
            }
            if !person.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(person.tags, id: \.self) { tag in
                        Chip(label: tag, color: AppTheme.tag)
                    }
                }
            }
        }
    }
}
