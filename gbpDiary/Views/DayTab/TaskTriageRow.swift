import SwiftUI
import SwiftData

// One inbox/triage row (parallel to EmailTriageRow): status + summary on the first line, then the
// grouped inline quick-set controls — project, due, scheduled, priority — and a prominent **Reviewed**
// action on the second. Reused by the Tasks-page Triage/Side-by-side views and the diary panel's Inbox.
struct TaskTriageRow: View {
    @Bindable var task: Task
    var onEdit: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var allProjects: [Project]
    @State private var editingProject = false
    @State private var showingLogTime = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TaskStatusMenu(task: task) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor).font(.system(size: 16)).frame(width: 20)
                }
                Text(task.summary)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(2)
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit() }
                Spacer(minLength: 8)
                reviewedButton
            }
            HStack(spacing: 6) {
                projectChip
                TriageDateChip(label: "Due", date: $task.dueAt, tint: AppTheme.destructive)
                TriageDateChip(label: "Sched", date: $task.scheduledAt, tint: AppTheme.accent)
                priorityPicker
                Spacer(minLength: 0)
            }
            .padding(.leading, 28)   // align controls under the summary
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button("Log time today…") { showingLogTime = true }
            Divider()
            Button("Reviewed") { task.markReviewed() }.disabled(!canReview)
        }
        .sheet(isPresented: $showingLogTime) {
            LogTimeSheet(presetTask: task, presetDate: Date())
        }
    }

    // A task must have a project before it can be reviewed out of the inbox.
    private var canReview: Bool { task.project != nil }

    private var reviewedButton: some View {
        Button { task.markReviewed() } label: {
            Label("Reviewed", systemImage: "checkmark.circle")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background((canReview ? AppTheme.completed : AppTheme.mutedText).opacity(0.16), in: Capsule())
                .foregroundStyle(canReview ? AppTheme.completed : AppTheme.mutedText)
        }
        .buttonStyle(.plain)
        .disabled(!canReview)
        .help(canReview ? "Mark reviewed — moves this task out of the inbox"
                        : "Assign a project before marking this task reviewed")
    }

    @ViewBuilder private var projectChip: some View {
        Button { editingProject = true } label: {
            Chip(label: task.project?.name ?? "No Project",
                 color: task.project == nil ? AppTheme.mutedText : AppTheme.project)
        }
        .buttonStyle(.plain)
        .help(task.project == nil ? "No project — click to choose" : "Project — click to change")
        .overlay(alignment: .bottomLeading) {
            FuzzyPickerField(
                allItems: allProjects,
                selectedItem: $task.project,
                label: { $0.name },
                chipColor: AppTheme.project,
                onCreateItem: makeProject,
                isPresented: $editingProject
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .allowsHitTesting(false)
        }
    }

    // One-click priority: tap L / M / H to set it; tap the active one again to clear (→ None).
    @ViewBuilder private var priorityPicker: some View {
        HStack(spacing: 3) {
            ForEach([TaskPriority.low, .medium, .high], id: \.self) { p in
                let active = task.priority == p
                Button { task.priority = active ? .none : p } label: {
                    Text(p.short)
                        .font(.caption2.weight(.semibold))
                        .frame(minWidth: 15)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(active ? priorityColor(p).opacity(0.22) : Color.secondary.opacity(0.10),
                                    in: Capsule())
                        .foregroundStyle(active ? priorityColor(p) : AppTheme.mutedText)
                        .overlay(active ? Capsule().stroke(priorityColor(p).opacity(0.75), lineWidth: 1) : nil)
                }
                .buttonStyle(.plain)
                .help("Priority \(p.displayName)")
            }
        }
    }

    private func priorityColor(_ p: TaskPriority) -> Color {
        switch p {
        case .high:   AppTheme.destructive
        case .medium: AppTheme.followUp
        case .low:    AppTheme.accent
        case .none:   AppTheme.mutedText
        }
    }

    private func makeProject(_ name: String) -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let project = Project(name: trimmed)
        modelContext.insert(project)
        return project
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
}

// A compact date chip with a graphical-picker popover and a Clear action; binds an optional Date.
private struct TriageDateChip: View {
    let label: String
    @Binding var date: Date?
    var tint: Color

    @State private var showing = false
    @State private var temp = Date()

    var body: some View {
        Button {
            temp = date ?? Calendar.current.date(byAdding: .day, value: 1,
                                                 to: Calendar.current.startOfDay(for: .now)) ?? .now
            showing = true
        } label: {
            Chip(label: date == nil ? label
                 : "\(label) \(date!.formatted(.dateTime.day().month(.abbreviated)))",
                 color: date == nil ? AppTheme.mutedText : tint)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                DatePicker(label, selection: $temp, displayedComponents: [.date])
                    .datePickerStyle(.graphical).labelsHidden()
                HStack {
                    if date != nil {
                        Button("Clear", role: .destructive) { date = nil; showing = false }
                    }
                    Spacer()
                    Button("Set") { date = temp; showing = false }.keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }
}
