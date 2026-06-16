import SwiftUI
import SwiftData

struct FocusBlockRow: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskTimeEntry.sortOrder) private var allEntries: [TaskTimeEntry]

    var block: FocusBlock
    var date: Date
    var meetings: [DayEntry] = []

    // @Query-driven so activity rows appear immediately without relationship-refresh lag.
    private var blockActivities: [TaskTimeEntry] {
        allEntries.filter { $0.focusBlock?.id == block.id }
            .sorted { $0.date < $1.date }
    }

    // Derive locally from blockActivities so the chip updates in sync with the query.
    private var netHours: Double {
        let spent = blockActivities.reduce(0.0) { $0 + $1.duration.hoursNormalized }
        return max(0, block.duration.hoursNormalized - spent)
    }

    @State private var isCollapsed = false
    @State private var showingEditor = false
    @State private var selectedMeetingMinutes: Minutes?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if !isCollapsed {
                VStack(alignment: .leading, spacing: 0) {
                    activityRows
                }
                .padding(.leading, 16)
            }
        }
        .sheet(item: $selectedMeetingMinutes) { m in
            MinutesDetailView(minutes: m, asSheet: true)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 6) {
            chevronButton

            HStack(alignment: .center, spacing: 6) {
                sourceIcon
                Text(block.displayLabel)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer(minLength: 0)
                durationChips
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { showingEditor = true }
            .padding(.trailing)
            .contextMenu {
                Button("Edit Focus Block…") { showingEditor = true }
            }
            .sheet(isPresented: $showingEditor) {
                if let record = block.dayRecord {
                    FocusBlockEditorSheet(dayRecord: record, existingBlock: block)
                }
            }
        }
        .padding(.leading)
        .padding(.vertical, 2)
    }

    private var chevronButton: some View {
        Button {
            isCollapsed.toggle()
        } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(width: 16, height: 22)
    }

    private var sourceIcon: some View {
        Image(systemName: "scope")
            .foregroundStyle(AppTheme.tag)
            .font(.system(size: 14))
            .frame(width: 18, height: 18)
    }

    private var durationChips: some View {
        HStack(spacing: 4) {
            Chip(label: block.slot.displayName, color: AppTheme.project)
            if netHours > 0 && !blockActivities.isEmpty {
                let netDur = Duration(value: netHours, unit: .h)
                Chip(label: netDur.displayString, color: AppTheme.duration)
            }
        }
    }

    @ViewBuilder
    private var meetingRows: some View {
        ForEach(meetings, id: \.id) { entry in
            if let minutes = entry.minutes {
                MeetingActivityRow(minutes: minutes, onTap: { selectedMeetingMinutes = minutes })
            }
        }
    }

    @ViewBuilder
    private var activityRows: some View {
        meetingRows
        ForEach(blockActivities) { entry in
            ActivityEntryRow(entry: entry)
        }
    }
}

private struct MeetingActivityRow: View {
    var minutes: Minutes
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.project)
                    .frame(width: 18)
                Text(minutes.summary ?? "Meeting")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.text)
                Spacer(minLength: 0)
                Chip(label: minutes.meetingAt.formatted(date: .omitted, time: .shortened), color: AppTheme.project)
                if let d = minutes.duration {
                    Chip(label: d.displayString, color: AppTheme.duration)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.cardRaised.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
            .padding(.trailing)
        }
        .padding(.leading)
        .padding(.vertical, 1)
    }
}

private struct ActivityEntryRow: View {
    var entry: TaskTimeEntry

    @State private var showingEdit = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)

            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                if let task = entry.task {
                    Text(task.summary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.text)
                } else {
                    Text("Unlinked activity")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedText)
                }

                if let comment = entry.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Chip(label: entry.date.formatted(date: .omitted, time: .shortened),
                     color: AppTheme.project)
                Chip(label: entry.duration.displayString, color: AppTheme.duration)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.cardRaised.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .onTapGesture { showingEdit = true }
            .padding(.trailing)
            .sheet(isPresented: $showingEdit) {
                LogTimeSheet(existingEntry: entry)
            }
        }
        .padding(.leading)
        .padding(.vertical, 1)
    }
}
