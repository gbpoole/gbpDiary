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
    var isCollapsed: Bool = false
    var onToggleCollapse: (() -> Void)? = nil
    var onBeforeStatusChange: (() -> Void)? = nil
    var onLogTime: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var showingFollowUpPicker = false
    @State private var followUpPickerDate = Date()
    @State private var showingLogTime = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            statusButton
            contentRow
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .font(AppTheme.bodyFont(size: 13))
        .contentShape(Rectangle())
        .contextMenu { contextMenuItems }
        .sheet(isPresented: $showingFollowUpPicker) {
            FollowUpDateSheet(
                initialDate: task.followUpAt ?? Calendar.current.date(byAdding: .day, value: 1, to: .now)!,
                onSave: { date in task.setFollowUp(date: date) },
                onRemove: task.followUpAt != nil ? { task.clearFollowUp() } : nil
            )
        }
        .sheet(isPresented: $showingLogTime) {
            LogTimeSheet(presetTask: task, presetDate: Date())
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
        case .todo:            AppTheme.mutedText
        case .started:         AppTheme.started
        case .completed:       AppTheme.completed
        case .cancelled:       AppTheme.mutedText
        case .followUpPending: AppTheme.followUp
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
            InlineEditableSingleLineText(
                placeholder: "",
                text: $task.summary,
                isFocused: isFocusedInline,
                focusBinding: fb,
                focusId: fid,
                struckThrough: task.status == .cancelled,
                foregroundColor: task.status == .cancelled ? AppTheme.mutedText : AppTheme.text,
                onIndent: onIndent,
                onOutdent: onOutdent,
                onMoveToPrevious: onMoveToPrevious,
                onMoveToNext: onMoveToNext
            )
        } else {
            Text(task.summary)
                .lineLimit(1)
                .strikethrough(task.status == .cancelled)
                .italic()
                .foregroundStyle(task.status == .cancelled ? AppTheme.mutedText : AppTheme.text)
        }
    }

    private var contentRow: some View {
        HStack(alignment: .center, spacing: 6) {
            inlineTitleView
            if let project = task.project {
                Chip(label: project.name, color: AppTheme.project)
            }
            if let assignee = task.assignee {
                Chip(label: assignee.name, color: AppTheme.person)
            }
            if let dur = task.duration {
                Chip(label: dur.displayString, color: AppTheme.duration)
            }
            ForEach(task.tags, id: \.self) { tag in
                Chip(label: tag, color: AppTheme.tag)
            }
            if task.status == .completed && task.followUpAt == nil {
                Button(action: { showingFollowUpPicker = true }) {
                    Image(systemName: "clock.badge.plus")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            if let fu = task.followUpAt {
                let overdue = fu < Calendar.current.startOfDay(for: Date())
                Button(action: { showingFollowUpPicker = true }) {
                    Chip(label: "↻ \(fu.formatted(.dateTime.day().month()))",
                         color: overdue ? AppTheme.destructive : AppTheme.followUp)
                }
                .buttonStyle(.plain)
            }
            InlineRowEditButton(action: onEdit)
            if !isFocusedInline {
                Spacer(minLength: 0)
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
        Button("Log time today…") {
            if let logTime = onLogTime {
                logTime()
            } else {
                showingLogTime = true
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            modelContext.delete(task)
        }
    }

    private func toggleStatus() {
        onBeforeStatusChange?()
        switch task.status {
        case .todo:
            task.status = .started
            task.updatedAt = Date()
        case .started:
            task.markCompleted()
        case .completed:
            task.markCancelled()
        case .followUpPending:
            task.markCancelled()
        case .cancelled:
            task.unmarkCancelled()
        }
    }
}

struct FollowUpDateSheet: View {
    let initialDate: Date
    let onSave: (Date) -> Void
    var onRemove: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date

    init(initialDate: Date, onSave: @escaping (Date) -> Void, onRemove: (() -> Void)? = nil) {
        self.initialDate = initialDate
        self.onSave = onSave
        self.onRemove = onRemove
        _selectedDate = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Follow-up date", selection: $selectedDate, displayedComponents: .date)
            }
            .navigationTitle("Set Follow-up Date")
            .toolbar {
                if let onRemove {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Remove Follow-up") { onRemove(); dismiss() }
                            .foregroundStyle(.red)
                    }
                }
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
            .font(AppTheme.interfaceFont(size: 10.5, weight: .regular))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppTheme.chipBackground(color))
            .foregroundStyle(color)
            .overlay(Capsule().stroke(color.opacity(0.85), lineWidth: 1))
            .clipShape(Capsule())
    }
}
