import SwiftUI
import SwiftData

struct TaskRowView: View {
    @Bindable var task: Task
    let onEdit: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusButton
            VStack(alignment: .leading, spacing: 3) {
                titleRow
                metaRow
                if !task.children.isEmpty {
                    childrenList
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu { contextMenuItems }
    }

    private var statusButton: some View {
        Button(action: toggleStatus) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.system(size: 17))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .padding(.top, 1)
    }

    private var statusIcon: String {
        switch task.status {
        case .open:            "circle"
        case .completed:       "checkmark.circle.fill"
        case .cancelled:       "xmark.circle.fill"
        case .followUpPending: "arrow.clockwise.circle.fill"
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .open:            .secondary
        case .completed:       .green
        case .cancelled:       .secondary
        case .followUpPending: .orange
        }
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Text(task.title)
                .strikethrough(task.status == .cancelled)
                .foregroundStyle(task.status == .cancelled ? .secondary : .primary)
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
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
        if task.status != .completed {
            Button("Mark Complete") { task.markCompleted() }
        } else {
            Button("Unmark Complete") { task.unmarkCompleted() }
        }
        if task.status != .cancelled {
            Button("Cancel Task") { task.markCancelled() }
        } else {
            Button("Uncancel") { task.unmarkCancelled() }
        }
        Divider()
        Button("Delete", role: .destructive) {
            modelContext.delete(task)
        }
    }

    private func toggleStatus() {
        switch task.status {
        case .open:            task.markCompleted()
        case .completed:       task.unmarkCompleted()
        case .cancelled:       task.unmarkCancelled()
        case .followUpPending: task.markFollowUpDone()
        }
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
