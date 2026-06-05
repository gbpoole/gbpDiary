import SwiftUI
import SwiftData

struct ActivitySection: View {
    @Query(sort: \FocusBlock.sortOrder) private var allFocusBlocks: [FocusBlock]

    var dayRecord: DayRecord?
    var date: Date
    var todayEntries: [TaskTimeEntry]

    @State private var showingAddFocusBlock = false

    // @Query-driven so new blocks appear immediately without relationship-refresh lag.
    private var blocks: [FocusBlock] {
        guard let id = dayRecord?.id else { return [] }
        return allFocusBlocks.filter { $0.dayRecord?.id == id }
    }

    var body: some View {
        DaySectionHeader(title: "Activity") {
            showingAddFocusBlock = true
        }

        let unspecified = todayEntries.filter { $0.focusBlock == nil }

        ForEach(blocks) { block in
            FocusBlockRow(block: block, date: date)
        }

        if !unspecified.isEmpty {
            unspecifiedSection(unspecified)
        }

        if !blocks.isEmpty || !unspecified.isEmpty {
            totalFooter(blocks: blocks, unspecified: unspecified)
        }

        if let record = dayRecord {
            Color.clear
                .sheet(isPresented: $showingAddFocusBlock) {
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
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .padding(.leading, 2)

                if let task = entry.task {
                    Text(task.summary)
                        .font(.subheadline)
                } else {
                    Text("Unlinked entry")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
                Chip(label: entry.duration.displayString, color: .gray)

                if let comment = entry.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.03))
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
