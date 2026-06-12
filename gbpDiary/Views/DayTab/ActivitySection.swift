import SwiftUI
import SwiftData

struct ActivitySection: View {
    @Query(sort: \FocusBlock.sortOrder) private var allFocusBlocks: [FocusBlock]

    var dayRecord: DayRecord?
    var date: Date
    var todayEntries: [TaskTimeEntry]
    var meetings: [DayEntry] = []
    // Lazily creates the DayRecord for `date` if it does not exist yet.
    var findOrCreateDayRecord: (() -> DayRecord)? = nil

    @State private var showingAddFocusBlock = false
    @State private var editorDayRecord: DayRecord?

    // @Query-driven so new blocks appear immediately without relationship-refresh lag.
    private var blocks: [FocusBlock] {
        guard let id = dayRecord?.id else { return [] }
        return allFocusBlocks.filter { $0.dayRecord?.id == id }
    }

    private func meetings(for block: FocusBlock) -> [DayEntry] {
        switch block.slot {
        case .allDay:
            return meetings
        case .morning, .afternoon:
            return meetings.filter { entry in
                guard let m = entry.minutes else { return false }
                return MeetingSlotClassifier.slots(for: m, on: date).contains(block.slot)
            }
        }
    }

    // No more slots can be added if an all-day block exists, or both morning and afternoon are taken.
    private var canAddBlock: Bool {
        let taken = Set(blocks.map(\.slot))
        if taken.contains(.allDay) { return false }
        return !taken.contains(.morning) || !taken.contains(.afternoon)
    }

    var body: some View {
        DaySectionHeader(title: "Activity", onAdd: canAddBlock ? {
            editorDayRecord = findOrCreateDayRecord?() ?? dayRecord
            showingAddFocusBlock = true
        } : nil)

        let unspecified = todayEntries.filter { $0.focusBlock == nil }

        ForEach(blocks) { block in
            FocusBlockRow(block: block, date: date, meetings: meetings(for: block))
        }

        if !unspecified.isEmpty {
            unspecifiedSection(unspecified)
        }

        if !blocks.isEmpty || !unspecified.isEmpty {
            totalFooter(blocks: blocks, unspecified: unspecified)
        }

        if let record = editorDayRecord {
            Color.clear
                .sheet(isPresented: $showingAddFocusBlock, onDismiss: { editorDayRecord = nil }) {
                    FocusBlockEditorSheet(dayRecord: record)
                }
        }
    }

    @ViewBuilder
    private func unspecifiedSection(_ entries: [TaskTimeEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Unspecified")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 38)
                    .padding(.vertical, 4)
                Spacer()
            }
            ForEach(entries) { entry in
                UnspecifiedActivityRow(entry: entry)
            }
        }
    }

    private func totalFooter(blocks: [FocusBlock], unspecified: [TaskTimeEntry]) -> some View {
        let blockHours = blocks.reduce(0.0) { $0 + $1.duration.hoursNormalized }
        let unspecifiedHours = unspecified.reduce(0.0) { $0 + $1.duration.hoursNormalized }
        let total = blockHours + unspecifiedHours
        let totalDur = Duration(value: total, unit: .h)

        return HStack {
            Spacer()
            Text("Total: \(totalDur.displayString)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.trailing)
                .padding(.bottom, 4)
        }
    }
}

private struct UnspecifiedActivityRow: View {
    @Environment(\.modelContext) private var modelContext
    var entry: TaskTimeEntry

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)

            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.mutedText)
                    .frame(width: 18)
                    .padding(.leading, 2)

                if let task = entry.task {
                    Text(task.summary)
                        .font(.subheadline)
                } else {
                    Text("Unlinked entry")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.mutedText)
                }

                Spacer(minLength: 0)
                Chip(label: entry.duration.displayString, color: AppTheme.duration)

                if let comment = entry.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.cardRaised.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(.trailing)
            .contextMenu {
                Button("Delete", role: .destructive) {
                    modelContext.delete(entry)
                }
            }
        }
        .padding(.leading)
        .padding(.vertical, 1)
    }
}
