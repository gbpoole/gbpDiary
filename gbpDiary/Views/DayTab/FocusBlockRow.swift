import SwiftUI
import SwiftData

struct FocusBlockRow: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskTimeEntry.sortOrder) private var allEntries: [TaskTimeEntry]

    var block: FocusBlock
    var date: Date

    // @Query-driven so activity rows appear immediately without relationship-refresh lag.
    private var blockActivities: [TaskTimeEntry] {
        allEntries.filter { $0.focusBlock?.id == block.id }
    }

    // Derive locally from blockActivities so the chip updates in sync with the query.
    private var netHours: Double {
        let spent = blockActivities.reduce(0.0) { $0 + $1.duration.hoursNormalized }
        return max(0, block.duration.hoursNormalized - spent)
    }

    @State private var isCollapsed = false
    @State private var showingLogTime = false
    @State private var showingEditor = false
    @State private var showingDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if !isCollapsed {
                activityRows
            }
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
                addActivityButton
                editButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.trailing)
            .contextMenu {
                Button("Edit Focus Block…") { showingEditor = true }
                Divider()
                Button("Delete Focus Block…", role: .destructive) {
                    showingDeleteAlert = true
                }
            }
            .sheet(isPresented: $showingEditor) {
                if let record = block.dayRecord {
                    FocusBlockEditorSheet(dayRecord: record, existingBlock: block)
                }
            }
            .sheet(isPresented: $showingLogTime) {
                LogTimeSheet(presetFocusBlock: block, presetDate: date)
            }
            .alert("Delete Focus Block?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    modelContext.delete(block)
                }
            } message: {
                if !blockActivities.isEmpty {
                    Text("This will remove the focus block and unlink its \(blockActivities.count) activit\(blockActivities.count == 1 ? "y" : "ies").")
                } else {
                    Text("This will permanently remove the focus block.")
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
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(width: 16, height: 22)
    }

    private var sourceIcon: some View {
        Group {
            if block.task != nil {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "folder")
                    .foregroundStyle(.blue)
            }
        }
        .font(.system(size: 14))
        .frame(width: 18, height: 18)
    }

    private var durationChips: some View {
        HStack(spacing: 4) {
            Chip(label: block.duration.displayString, color: .gray)
            if netHours > 0 && !blockActivities.isEmpty {
                let netDur = Duration(value: netHours, unit: .h)
                Text("\(netDur.displayString) unspecified")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var addActivityButton: some View {
        Button {
            showingLogTime = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Log activity in this focus block")
    }

    private var editButton: some View {
        InlineRowEditButton { showingEditor = true }
    }

    @ViewBuilder
    private var activityRows: some View {
        ForEach(blockActivities) { entry in
            ActivityEntryRow(entry: entry)
        }
    }
}

private struct ActivityEntryRow: View {
    @Environment(\.modelContext) private var modelContext
    var entry: TaskTimeEntry

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)

            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .padding(.leading, 2)

                if let task = entry.task {
                    Text(task.summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                } else {
                    Text("Unlinked activity")
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
