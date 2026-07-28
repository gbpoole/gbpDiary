import SwiftUI
import SwiftData

struct ActivitySection: View {
    @Query(sort: \FocusBlock.sortOrder) private var allFocusBlocks: [FocusBlock]
    @Environment(\.modelContext) private var modelContext

    var dayRecord: DayRecord?
    var date: Date
    var todayEntries: [TaskTimeEntry]
    var meetings: [DayEntry] = []
    var completedTasks: [Task] = []
    // Lazily creates the DayRecord for `date` if it does not exist yet.
    var findOrCreateDayRecord: (() -> DayRecord)? = nil
    /// Trigger bindings wired from DayPageContent's action bar.
    /// Default to .constant(false) so callers that don't use the action bar still compile.
    var logTimeTrigger: Binding<Bool> = .constant(false)
    var focusBlockTrigger: Binding<Bool> = .constant(false)
    var meetingTrigger: Binding<Bool> = .constant(false)

    @State private var showingAddFocusBlock = false
    @State private var showingLogTime = false
    @State private var selectedMeetingMinutes: Minutes?
    @State private var isNewMeeting = false
    @State private var editorDayRecord: DayRecord?

    // @Query-driven so new blocks appear immediately without relationship-refresh lag.
    private var blocks: [FocusBlock] {
        guard let id = dayRecord?.id else { return [] }
        return allFocusBlocks.filter { $0.dayRecord?.id == id }
    }

    // Block membership is derived purely from each entry's time — nothing is stored. The block
    // whose range contains the time owns the entry; entries covered by no block are standalone.
    private func entries(for block: FocusBlock) -> [TaskTimeEntry] {
        todayEntries.filter { FocusBlockAssignment.containingBlock(for: $0.date, blocks: blocks)?.id == block.id }
    }

    // Entries not covered by any block's range — rendered standalone, at block indent level.
    private var standaloneEntries: [TaskTimeEntry] {
        todayEntries.filter { FocusBlockAssignment.containingBlock(for: $0.date, blocks: blocks) == nil }
    }

    private enum ActivityRowItem: Identifiable {
        case block(FocusBlock)
        case entry(TaskTimeEntry)
        var id: String {
            switch self {
            case .block(let b): "b-\(b.id.uuidString)"
            case .entry(let e): "e-\(e.id.uuidString)"
            }
        }
    }

    // The time a block's range begins, used to order blocks against standalone entries.
    private func slotStart(_ block: FocusBlock) -> Date {
        let cal = Calendar.current
        switch block.slot {
        case .morning, .allDay: return cal.startOfDay(for: date)
        case .afternoon:        return DaySlotBoundary.morningAfternoon(on: date)
        case .evening:          return block.startTime ?? cal.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
        }
    }

    // Blocks + standalone entries, interleaved in chronological order.
    private var activityItems: [ActivityRowItem] {
        let blockItems = blocks.map { (slotStart($0), ActivityRowItem.block($0)) }
        let entryItems = standaloneEntries.map { ($0.date, ActivityRowItem.entry($0)) }
        return (blockItems + entryItems).sorted { $0.0 < $1.0 }.map(\.1)
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
        case .evening:
            return []
        }
    }

    // Meetings not already shown inside a FocusBlock, sorted by start time.
    private var standaloneMeetings: [Minutes] {
        let assignedMinutesIds = Set(
            blocks.flatMap { meetings(for: $0) }.compactMap { $0.minutes?.id }
        )
        return meetings
            .compactMap(\.minutes)
            .filter { !assignedMinutesIds.contains($0.id) }
            .sorted { $0.meetingAt < $1.meetingAt }
    }

    // No more slots can be added if an all-day block exists, or both morning and afternoon are taken.
    private var canAddBlock: Bool {
        let taken = Set(blocks.map(\.slot))
        if !taken.contains(.evening) { return true }   // an evening block is always addable
        if taken.contains(.allDay) { return false }
        return !taken.contains(.morning) || !taken.contains(.afternoon)
    }

    var body: some View {
        let hasContent = !blocks.isEmpty || !todayEntries.isEmpty
            || !standaloneMeetings.isEmpty || !completedTasks.isEmpty

        activityHeader

        if hasContent {
            // Focus blocks and any standalone (out-of-range) entries, interleaved by time.
            ForEach(activityItems) { item in
                switch item {
                case .block(let block):
                    FocusBlockRow(block: block, date: date, entries: entries(for: block), meetings: meetings(for: block))
                case .entry(let entry):
                    ActivityEntryRow(entry: entry)
                }
            }

            ForEach(standaloneMeetings, id: \.id) { minutes in
                StandaloneMeetingRow(minutes: minutes)
            }

            ForEach(completedTasks) { task in
                CompletedTaskActivityRow(task: task)
            }
        } else {
            Text("No activity logged for this day.")
                .foregroundStyle(.tertiary)
                .font(.callout)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }

        if let record = editorDayRecord {
            Color.clear
                .frame(width: 0, height: 0)
                .sheet(isPresented: $showingAddFocusBlock, onDismiss: { editorDayRecord = nil }) {
                    FocusBlockEditorSheet(dayRecord: record)
                }
        }

        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: logTimeTrigger.wrappedValue) { _, triggered in
                guard triggered else { return }
                showingLogTime = true
                logTimeTrigger.wrappedValue = false
            }
            .onChange(of: focusBlockTrigger.wrappedValue) { _, triggered in
                guard triggered else { return }
                editorDayRecord = findOrCreateDayRecord?() ?? dayRecord
                showingAddFocusBlock = true
                focusBlockTrigger.wrappedValue = false
            }
            .onChange(of: meetingTrigger.wrappedValue) { _, triggered in
                guard triggered else { return }
                addMeeting()
                meetingTrigger.wrappedValue = false
            }
            .sheet(isPresented: $showingLogTime) {
                LogTimeSheet(presetDate: date)
            }

        Color.clear
            .frame(width: 0, height: 0)
            .sheet(item: $selectedMeetingMinutes) { m in
                MinutesDetailView(minutes: m, asSheet: true, isNew: isNewMeeting).presentationSizing(.fitted)
            }
    }

    // MARK: - Activity header

    // Standard capacity from non-evening blocks + standalone/meeting/completed hours.
    private var totalHours: Double {
        let standardBlockHours = blocks.filter { !$0.isOvertime }.reduce(0.0) { $0 + $1.duration.hoursNormalized }
        let standaloneHours = standaloneEntries.reduce(0.0) { $0 + $1.duration.hoursNormalized }
        let meetingHours = standaloneMeetings.compactMap(\.duration).reduce(0.0) { $0 + $1.hoursNormalized }
        let taskHours = completedTasks.compactMap(\.duration).reduce(0.0) { $0 + $1.hoursNormalized }
        return standardBlockHours + standaloneHours + meetingHours + taskHours
    }
    private var overtimeHours: Double {
        blocks.filter { $0.isOvertime }.flatMap { entries(for: $0) }.reduce(0.0) { $0 + $1.duration.hoursNormalized }
    }

    private var activityHeader: some View {
        HStack(spacing: 8) {
            Text("Activity")
                .font(AppTheme.interfaceFont(size: 12, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.mutedText)
            Spacer()
            if overtimeHours > 0 {
                Text("Overtime \(Duration(value: overtimeHours, unit: .h).displayString)")
                    .font(AppTheme.interfaceFont(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            if totalHours > 0 {
                Text("Total \(Duration(value: totalHours, unit: .h).displayString)")
                    .font(AppTheme.interfaceFont(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .background(AppTheme.background)
    }

    // MARK: - Add meeting

    private func addMeeting() {
        let record = findOrCreateDayRecord?() ?? dayRecord
        guard let record else { return }
        let meeting = Minutes(meetingAt: nearestQuarterHour())
        meeting.duration = Duration(value: 1, unit: .h)
        modelContext.insert(meeting)
        let entry = DayEntry(kind: .meeting, text: "",
                             sortOrder: (record.entries.map(\.sortOrder).max() ?? -1) + 1)
        entry.minutes = meeting
        entry.dayRecord = record
        modelContext.insert(entry)
        isNewMeeting = true
        selectedMeetingMinutes = meeting
    }

    private func nearestQuarterHour() -> Date {
        let quarterHour = 15.0 * 60.0
        let now = Date()
        let interval = now.timeIntervalSinceReferenceDate
        let rounded = (interval / quarterHour).rounded() * quarterHour
        let roundedNow = Date(timeIntervalSinceReferenceDate: rounded)
        let cal = Calendar.current
        let hour = cal.component(.hour, from: roundedNow)
        let minute = cal.component(.minute, from: roundedNow)
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

}

private struct StandaloneMeetingRow: View {
    let minutes: Minutes
    var onTap: (() -> Void)? = nil

    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.project)
                    .frame(width: 18)
                Text(minutes.summary ?? "Meeting")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    MeetingDeleteButton(minutes: minutes)
                        .frame(width: 24, alignment: .center)
                    Group {
                        if let project = minutes.projects.first {
                            Chip(label: project.name, color: AppTheme.project)
                        }
                    }
                    Chip(label: minutes.meetingAt.formatted(date: .omitted, time: .shortened),
                         color: AppTheme.project)
                    Group {
                        if let d = minutes.duration {
                            Chip(label: d.displayString, color: AppTheme.duration)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.cardRaised.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .onTapGesture { workspace.openInNewTab(.minutes(minutes.persistentModelID)) }
            .padding(.trailing)
        }
        .padding(.leading)
        .padding(.vertical, 1)
    }
}

private struct CompletedTaskActivityRow: View {
    let task: Task

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.completed)
                    .frame(width: 18)
                    .padding(.leading, 2)
                Text(task.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.text)
                Spacer(minLength: 0)
                if let d = task.duration {
                    Chip(label: d.displayString, color: AppTheme.duration)
                }
                if let at = task.completedAt {
                    Text(at.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.cardRaised.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(.trailing)
        }
        .padding(.leading)
        .padding(.vertical, 1)
    }
}

