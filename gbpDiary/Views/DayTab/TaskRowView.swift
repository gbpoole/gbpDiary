import SwiftUI
import SwiftData

struct TaskRowView: View {
    @Bindable var task: Task
    let onEdit: () -> Void

    // Optional inline-editing parameters (used by EntryRowView in the day/week view).
    // When set, the title renders as an editable TextField instead of Text.
    var inlineEditing: Bool = false
    var focusBinding: FocusState<UUID?>.Binding? = nil
    var focusId: UUID? = nil
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil
    var onIndent: (() -> Void)? = nil
    var onOutdent: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var showingFollowUpPicker = false
    @State private var followUpPickerDate = Date()

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            statusButton
            VStack(alignment: .leading, spacing: 0) {
                contentRow
                if !task.children.isEmpty {
                    childrenList
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu { contextMenuItems }
        .sheet(isPresented: $showingFollowUpPicker) {
            FollowUpDateSheet(
                initialDate: task.followUpAt ?? Calendar.current.date(byAdding: .day, value: 1, to: .now)!,
                onSave: { date in task.setFollowUp(date: date) }
            )
        }
    }

    private var statusButton: some View {
        Button(action: toggleStatus) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.system(size: 17))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
    }

    private var statusIcon: String {
        switch task.status {
        case .todo:            "circle"
        case .started:         "play.circle.fill"
        case .completed:       "checkmark.circle.fill"
        case .cancelled:       "xmark.circle.fill"
        case .followUpPending: "arrow.clockwise.circle.fill"
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .todo:            .secondary
        case .started:         .blue
        case .completed:       .green
        case .cancelled:       .secondary
        case .followUpPending: .orange
        }
    }

    // True only when this specific row is the active inline editor.
    private var isFocusedInline: Bool {
        guard inlineEditing, let fb = focusBinding, let fid = focusId else { return false }
        return fb.wrappedValue == fid
    }

    // Title element: always keeps both Text (layout/display) and TextField (focus
    // machinery) in the hierarchy. The TextField is collapsed to zero width when
    // unfocused so it doesn't affect layout, but stays present so SwiftUI can
    // assign focus to it the instant the entry is navigated to via arrow keys.
    @ViewBuilder
    private var inlineTitleView: some View {
        if inlineEditing, let fb = focusBinding, let fid = focusId {
            ZStack(alignment: .leading) {
                Text(task.summary.isEmpty ? " " : task.summary)
                    .lineLimit(1)
                    .strikethrough(task.status == .cancelled)
                    .foregroundStyle(task.status == .cancelled ? Color.secondary : Color.primary)
                    .opacity(isFocusedInline ? 0 : 1)
                TextField("", text: $task.summary)
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .focused(fb, equals: fid)
                    .foregroundStyle(task.status == .cancelled ? Color.secondary : Color.primary)
                    .frame(maxWidth: isFocusedInline ? .infinity : 0)
                    .clipped()
                    .opacity(isFocusedInline ? 1 : 0)
                    .allowsHitTesting(isFocusedInline)
                    .entryInlineKeyHandling(
                        onIndent: onIndent,
                        onOutdent: onOutdent,
                        onMoveToPrevious: onMoveToPrevious,
                        onMoveToNext: onMoveToNext
                    )
            }
            .frame(maxWidth: isFocusedInline ? .infinity : nil)
            .contentShape(Rectangle())
            .onTapGesture { fb.wrappedValue = fid }
        } else {
            Text(task.summary)
                .lineLimit(1)
                .strikethrough(task.status == .cancelled)
                .foregroundStyle(task.status == .cancelled ? Color.secondary : Color.primary)
        }
    }

    private var contentRow: some View {
        HStack(alignment: .center, spacing: 6) {
            inlineTitleView
            if let project = task.project {
                Chip(label: project.name, color: .blue)
            }
            if let assignee = task.assignee {
                Chip(label: assignee.name, color: .purple)
            }
            if let dur = task.duration {
                Chip(label: dur.displayString, color: .gray)
            }
            ForEach(task.tags, id: \.self) { tag in
                Chip(label: tag, color: .teal)
            }
            if let fu = task.followUpAt {
                let overdue = fu < Calendar.current.startOfDay(for: Date())
                Chip(label: "↻ \(fu.formatted(.dateTime.day().month()))",
                     color: overdue ? .red : .orange)
            }
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            if !isFocusedInline {
                Spacer(minLength: 0)
            }
        }
    }

    private var childrenList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(task.children.sorted(by: { $0.createdAt < $1.createdAt })) { child in
                TaskRowView(task: child, onEdit: onEdit)
                    .padding(.leading, 20)
            }
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Edit…", action: onEdit)
        Divider()
        if task.status != .todo && task.status != .started {
            Button("Reopen") {
                switch task.status {
                case .completed:       task.unmarkCompleted()
                case .cancelled:       task.unmarkCancelled()
                case .followUpPending: task.unmarkCompleted()
                default: break
                }
            }
        }
        if task.status != .completed {
            Button("Mark Complete") { task.markCompleted() }
        }
        Button("Set Follow-up Date…") {
            followUpPickerDate = task.followUpAt
                ?? Calendar.current.date(byAdding: .day, value: 1,
                                         to: Calendar.current.startOfDay(for: .now))!
            showingFollowUpPicker = true
        }
        if task.status != .cancelled {
            Button("Cancel Task") { task.markCancelled() }
        }
        Divider()
        Button("Delete", role: .destructive) {
            modelContext.delete(task)
        }
    }

    private func toggleStatus() {
        switch task.status {
        case .todo:
            task.status = .started
            task.updatedAt = Date()
        case .started:
            task.markCompleted()
        case .completed:
            let tomorrow = Calendar.current.date(
                byAdding: .day, value: 1,
                to: Calendar.current.startOfDay(for: .now))!
            task.setFollowUp(date: tomorrow)
        case .followUpPending:
            task.markCancelled()
        case .cancelled:
            task.unmarkCancelled()
        }
    }
}

private struct FollowUpDateSheet: View {
    let initialDate: Date
    let onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date

    init(initialDate: Date, onSave: @escaping (Date) -> Void) {
        self.initialDate = initialDate
        self.onSave = onSave
        _selectedDate = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Follow-up date", selection: $selectedDate, displayedComponents: .date)
            }
            .navigationTitle("Set Follow-up Date")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(selectedDate); dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 140)
        #endif
    }
}

struct Chip: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
