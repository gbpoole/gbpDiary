import SwiftUI
import SwiftData

struct DayView: View {
    let date: Date

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Task.createdAt) private var allTasks: [Task]
    @State private var showingAddTask = false
    @State private var editingTask: Task?

    private var dayStart: Date { Calendar.current.startOfDay(for: date) }
    private var dayEnd: Date { Calendar.current.date(byAdding: .day, value: 1, to: dayStart)! }

    var scheduled: [Task] {
        allTasks.filter {
            guard let s = $0.scheduledAt else { return false }
            return s >= dayStart && s < dayEnd && $0.status == .open
        }
    }

    var followUpsDue: [Task] {
        allTasks.filter {
            guard let fu = $0.followUpAt else { return false }
            return fu < dayEnd && $0.status == .followUpPending
        }
    }

    var backlog: [Task] {
        allTasks.filter {
            $0.status == .open && $0.parent == nil &&
            ($0.scheduledAt == nil || $0.scheduledAt! < dayStart)
        }
    }

    var completedToday: [Task] {
        allTasks.filter {
            guard let c = $0.completedAt else { return false }
            return c >= dayStart && c < dayEnd
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                dayHeader

                if !scheduled.isEmpty {
                    SectionHeader(title: "Scheduled")
                    ForEach(scheduled) { task in
                        TaskRowView(task: task, onEdit: { editingTask = task })
                    }
                }

                if !followUpsDue.isEmpty {
                    SectionHeader(title: "Follow-ups Due")
                    ForEach(followUpsDue) { task in
                        TaskRowView(task: task, onEdit: { editingTask = task })
                    }
                }

                SectionHeader(title: "Backlog")
                if backlog.isEmpty {
                    Text("Nothing in the backlog.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                } else {
                    ForEach(backlog) { task in
                        TaskRowView(task: task, onEdit: { editingTask = task })
                    }
                }

                if !completedToday.isEmpty {
                    SectionHeader(title: "Completed Today")
                    ForEach(completedToday) { task in
                        TaskRowView(task: task, onEdit: { editingTask = task })
                    }
                }

                QuickAddBar(onAdd: { showingAddTask = true })
                    .padding(.top, 8)
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showingAddTask) {
            TaskEditorSheet(task: nil, defaultDate: date)
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: date)
        }
    }

    private var dayHeader: some View {
        Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year())
            .font(.title2.bold())
            .padding(.horizontal)
            .padding(.bottom, 4)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }
}

private struct QuickAddBar: View {
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("+ Task", action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

#Preview {
    DayView(date: Date())
        .modelContainer(for: [Task.self, DayRecord.self, Project.self,
                               Person.self, Institution.self, Minutes.self],
                        inMemory: true)
        .frame(width: 600, height: 700)
}
