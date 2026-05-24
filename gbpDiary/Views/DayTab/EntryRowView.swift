import SwiftUI
import SwiftData

struct EntryRowView: View {
    @Bindable var entry: DayEntry
    var focusedEntryId: FocusState<UUID?>.Binding
    var onAddNoteAfter: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var editingTask: Task?

    var body: some View {
        Group {
            switch entry.kind {
            case .note:      noteRow
            case .task:      taskRow
            case .meeting:   meetingRow
            case .timesheet: timesheetRow
            }
        }
    }

    // MARK: - Note

    private var noteRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
            TextField("", text: $entry.text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused(focusedEntryId, equals: entry.id)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        entry.text += "\n"
                        return .handled
                    }
                    onAddNoteAfter?()
                    return .handled
                }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .contextMenu { deleteButton }
    }

    // MARK: - Task

    private var taskRow: some View {
        Group {
            if let task = entry.task {
                TaskRowView(task: task, onEdit: { editingTask = task })
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                    Text("(missing task)").foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.vertical, 5)
                .contextMenu { deleteButton }
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: entry.createdAt)
        }
    }

    // MARK: - Meeting

    private var meetingRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(.blue)
                .frame(width: 22, height: 22)
            if let m = entry.minutes {
                Text(m.summary ?? m.meetingAt.formatted(.dateTime.hour().minute().day().month()))
            } else {
                TextField("Meeting description", text: $entry.text)
                    .textFieldStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .contextMenu { deleteButton }
    }

    // MARK: - Timesheet

    private var timesheetRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "clock")
                .foregroundStyle(.orange)
                .frame(width: 22, height: 22)
            TextField("Description", text: $entry.text)
                .textFieldStyle(.plain)
            if let dur = entry.duration {
                Chip(label: dur.displayString, color: .orange)
            }
            if let proj = entry.project {
                Chip(label: proj.name, color: .blue)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .contextMenu { deleteButton }
    }

    // MARK: - Shared

    private var deleteButton: some View {
        Button("Delete", role: .destructive) {
            modelContext.delete(entry)
        }
    }
}
