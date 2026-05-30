import SwiftUI
import SwiftData

struct MeetingTaskListView: View {
    @Bindable var minutes: Minutes
    var onDropDiaryEntry: ((String) -> Bool)? = nil
    @Environment(\.modelContext) private var modelContext
    @State private var activeDropZone: Int?
    @State private var editingTask: Task?

    private var sortedTasks: [Task] {
        minutes.newTasks.sorted { $0.meetingTaskSortOrder < $1.meetingTaskSortOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Tasks")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)

            taskDropZone(at: 0)
            ForEach(Array(sortedTasks.enumerated()), id: \.element.id) { index, task in
                taskRow(task)
                    .draggable(task.id.uuidString)
                taskDropZone(at: index + 1)
            }
        }
        .padding(.bottom, 4)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: minutes.meetingAt)
        }
    }

    private func taskRow(_ task: Task) -> some View {
        HStack(spacing: 8) {
            Button { cycleStatus(task) } label: {
                Image(systemName: statusIcon(task.status))
                    .foregroundStyle(statusColor(task.status))
                    .font(.system(size: 15))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            Text(task.summary.isEmpty ? "(untitled)" : task.summary)
                .lineLimit(1)
                .strikethrough(task.status == .completed || task.status == .cancelled)
                .foregroundStyle(task.status == .cancelled ? Color.secondary : Color.primary)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { editingTask = task }
        .contextMenu {
            Button("Edit Task") { editingTask = task }
            Divider()
            Button("Remove from Meeting") { task.originMinutes = nil }
            Button("Delete Task", role: .destructive) {
                task.originMinutes = nil
                modelContext.delete(task)
            }
        }
    }

    private func taskDropZone(at index: Int) -> some View {
        ZStack {
            Color.clear.frame(height: 4)
            if activeDropZone == index {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 8)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first,
                  let id = UUID(uuidString: uuidString)
            else { return false }
            if let dragged = sortedTasks.first(where: { $0.id == id }) {
                moveTask(dragged, toDropIndex: index)
                activeDropZone = nil
                return true
            }
            // Diary entry (DayEntry UUID) dropped over the meeting task area — hand off to parent.
            if let handler = onDropDiaryEntry { return handler(uuidString) }
            return false
        } isTargeted: { targeted in
            activeDropZone = targeted ? index : nil
        }
    }

    private func moveTask(_ dragged: Task, toDropIndex dropIndex: Int) {
        var sorted = sortedTasks
        guard let fromIndex = sorted.firstIndex(where: { $0.id == dragged.id }) else { return }
        sorted.remove(at: fromIndex)
        let target = min(dropIndex > fromIndex ? dropIndex - 1 : dropIndex, sorted.count)
        sorted.insert(dragged, at: target)
        for (i, task) in sorted.enumerated() { task.meetingTaskSortOrder = i }
    }

    private func cycleStatus(_ task: Task) {
        switch task.status {
        case .todo:      task.status = .started
        case .started:   task.markCompleted()
        case .completed: task.unmarkCompleted()
        default:         break
        }
    }

    private func statusIcon(_ status: TaskStatus) -> String {
        switch status {
        case .todo:            "circle"
        case .started:         "play.circle.fill"
        case .completed:       "checkmark.circle.fill"
        case .cancelled:       "xmark.circle.fill"
        case .followUpPending: "arrow.clockwise.circle.fill"
        }
    }

    private func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .todo:            .secondary
        case .started:         .blue
        case .completed:       .green
        case .cancelled:       .secondary
        case .followUpPending: .orange
        }
    }
}
