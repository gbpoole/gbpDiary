import SwiftUI
import SwiftData

struct EntryDetailPanel: View {
    let item: DiaryItem
    let onDismiss: () -> Void

    var body: some View {
        Group {
            switch item {
            case .task(let task):
                TaskDetailPanel(task: task, onDismiss: onDismiss)
            case .entry(let entry):
                if case let .meeting(minutes) = entry.detailTarget {
                    MeetingDetailPanel(minutes: minutes, onDismiss: onDismiss)
                } else {
                    EmptyView()
                }
            }
        }
    }
}

private struct TaskDetailPanel: View {
    @Bindable var task: Task
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                Text(task.summary)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            // Chips
            FlowLayout(spacing: 6) {
                statusChip
                if let project = task.project {
                    Chip(label: project.name, color: .blue)
                }
                if let assignee = task.assignee {
                    Chip(label: assignee.name, color: .purple)
                }
                if let dur = task.duration {
                    Chip(label: dur.displayString, color: .gray)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            Divider()

            Spacer()
        }
    }

    private var statusChip: some View {
        let label: String
        let color: Color
        switch task.status {
        case .todo:
            label = "To Do"; color = .secondary
        case .started:
            label = "Started"; color = .blue
        case .completed:
            label = "Completed"; color = .green
        case .cancelled:
            label = "Cancelled"; color = .secondary
        case .followUpPending:
            label = "Follow-up"; color = .orange
        }
        return Chip(label: label, color: color)
    }
}

private struct MeetingDetailPanel: View {
    @Bindable var minutes: Minutes
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                Text(minutes.summary ?? "Meeting")
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Text(minutes.meetingAt, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 6)

            if !minutes.attendees.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(minutes.attendees) { p in
                        Chip(label: p.name, color: .purple)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }

            if !minutes.projects.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(minutes.projects) { p in
                        Chip(label: p.name, color: .blue)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }

            Divider()

            Spacer()
        }
    }
}
