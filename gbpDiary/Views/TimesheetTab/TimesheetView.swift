import SwiftUI
import SwiftData

struct TimesheetView: View {
    @Query(sort: \Task.completedAt, order: .reverse) private var allTasks: [Task]
    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \TaskTimeEntry.date, order: .reverse) private var allEntries: [TaskTimeEntry]
    @Query private var allFocusBlocks: [FocusBlock]
    @Query private var allEmails: [EmailMessage]
    @Query private var allMeetings: [Minutes]

    @Environment(WorkspaceModel.self) private var workspace
    @State private var mailService = MailScriptService()
    @State private var selectedTask: Task?
    private let answerer = FoundationModelsChatAnswerer()

    @State private var selectedRange: TimesheetRange = .pastWeek
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var customEnd: Date = Date()

    private var rangeInterval: DateInterval {
        TimesheetComputation.rangeInterval(
            selectedRange: selectedRange,
            customStart: customStart,
            customEnd: customEnd
        )
    }

    private var entriesInRange: [TaskTimeEntry] {
        TimesheetComputation.entriesInRange(allEntries: allEntries, interval: rangeInterval)
    }

    // Legacy: tasks with no time entries that have a duration field set.
    private var legacyTasksInRange: [Task] {
        TimesheetComputation.tasksInRange(allTasks: allTasks, interval: rangeInterval)
            .filter { $0.timeEntries.isEmpty }
    }

    // Per-project time + the "what was done" narrative come from one shared, deterministic report
    // (also used by Chat). Hours split block capacity by in-block activity's project (via TimeLedger);
    // the narrative pairs each project's meetings, completed tasks, logged comments, and emails.
    private var rangeReport: ProjectActivityReport {
        ProjectActivityProjection.report(interval: rangeInterval.start..<rangeInterval.end,
                                         tasks: allTasks, emails: allEmails, meetings: allMeetings,
                                         focusBlocks: allFocusBlocks)
    }

    // Timesheet stays time-anchored: only projects with logged hours (enriched with their narrative).
    private var projectSections: [ProjectActivitySection] { rangeReport.sections.filter { $0.hours > 0 } }

    private var totalHours: Double { projectSections.reduce(0) { $0 + $1.hours } }
    private var totalTaskCount: Int {
        Set(entriesInRange.compactMap(\.task?.id)).union(Set(legacyTasksInRange.map(\.id))).count
    }
    private var overtime: Double {
        TimeLedgerProjection.ledger(focusBlocks: allFocusBlocks, tasks: allTasks, emails: allEmails,
                                    meetings: allMeetings, interval: rangeInterval.start..<rangeInterval.end).overtime
    }

    var body: some View {
        VStack(spacing: 0) {
            rangeBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    totalCard
                    projectBreakdown
                }
                .padding()
            }
        }
        .onAppear { answerer.prewarm() }   // warm the on-device model ahead of the first Summarise
        .sheet(item: $selectedTask) { task in
            TaskEditorSheet(task: task, defaultDate: task.completedAt ?? Date())
        }
    }

    private var rangeBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Range", selection: $selectedRange) {
                ForEach(TimesheetRange.allCases, id: \.self) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)
            if selectedRange == .custom {
                HStack {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, displayedComponents: .date)
                }
                .labelsHidden()
            }
        }
        .padding()
    }

    private var totalCard: some View {
        GroupBox("Total") {
            HStack {
                VStack(alignment: .leading) {
                    Text(TimeFormat.hours(totalHours))
                        .font(.largeTitle.bold())
                    Text("\(TimeFormat.days(totalHours))  ·  \(totalTaskCount) tasks")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if overtime > 0 {
                        Text("Includes \(TimeFormat.hours(overtime)) overtime")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private var projectBreakdown: some View {
        GroupBox("By Project") {
            if projectSections.isEmpty {
                Text("No logged time in this range.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(projectSections.enumerated()), id: \.element.projectName) { index, section in
                        ProjectActivitySectionView(section: section, totalHours: totalHours,
                                                   answerer: answerer, onOpen: open)
                        if index < projectSections.count - 1 { Divider().padding(.vertical, 2) }
                    }
                }
            }
        }
    }

    // Navigate a narrative bullet to its source (the kinds the report emits).
    private func open(_ source: ChatSourceReference) {
        switch source.navigationKind {
        case .meeting:
            if let m = allMeetings.first(where: { $0.id == source.navigationID }) {
                workspace.focusOrOpen(.minutes(m.persistentModelID))
            }
        case .task:
            selectedTask = allTasks.first { $0.id == source.navigationID }
        case .email:
            if let e = allEmails.first(where: { $0.id == source.navigationID }) {
                mailService.openMessage(e) { _ in }
            }
        case .project:
            if let p = projects.first(where: { $0.id == source.navigationID }) {
                workspace.focusOrOpen(.project(p.persistentModelID))
            }
        default:
            break
        }
    }
}

// One expandable project: the header keeps the time figures; expanding reveals the grouped "what was
// done" bullets (each tappable to its source) plus an on-demand, on-device prose summary. The summary
// only rephrases the app-built items — it never invents (rephrase-only contract).
private struct ProjectActivitySectionView: View {
    let section: ProjectActivitySection
    let totalHours: Double
    let answerer: FoundationModelsChatAnswerer
    let onOpen: (ChatSourceReference) -> Void

    @State private var expanded = true
    @State private var prose: String?
    @State private var proseError: String?
    @State private var isSummarizing = false
    @State private var summarizeToken: UUID?

    private var percent: Int { totalHours > 0 ? Int((section.hours / totalHours * 100).rounded()) : 0 }

    private struct ItemGroup { let title: String; let items: [ChatActivityItem] }
    private var groups: [ItemGroup] {
        let order: [(String, ChatActivityKind)] = [
            ("Meetings", .meeting), ("Completed", .completedTask),
            ("Logged notes", .loggedComment), ("Emails", .email),
        ]
        return order.compactMap { title, kind in
            let items = section.items.filter { $0.kind == kind }
            return items.isEmpty ? nil : ItemGroup(title: title, items: items)
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            expandedContent
        } label: {
            headerRow
        }
        .padding(.vertical, 4)
        .task(id: summarizeToken) { await runSummarize() }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(section.projectName).font(.headline)
            Spacer()
            Text(TimeFormat.hours(section.hours)).monospacedDigit()
            Text("·").foregroundStyle(.secondary)
            Text(TimeFormat.days(section.hours)).foregroundStyle(.secondary).monospacedDigit()
            Text("·").foregroundStyle(.secondary)
            Text(ChatTimeTotals.weeksText(section.distinctWeeks)).foregroundStyle(.secondary)
            Text("(\(percent)%)").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if section.items.isEmpty {
                Text("No recorded meetings, tasks, notes, or emails in this range.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.title.uppercased())
                            .font(.caption2).foregroundStyle(.secondary)
                        ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                            itemRow(item)
                        }
                    }
                }
            }
            summarizeArea
        }
        .padding(.top, 6)
        .padding(.leading, 4)
    }

    private func itemRow(_ item: ChatActivityItem) -> some View {
        let hasSource = item.source != nil
        return HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(item.label)
                .foregroundStyle(hasSource ? Color.accentColor : .primary)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .contentShape(Rectangle())
        .onTapGesture { if let s = item.source { onOpen(s) } }
    }

    private var summarizeArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    summarizeToken = UUID()
                } label: {
                    Label(isSummarizing ? "Summarising…" : "Summarise", systemImage: "sparkles")
                }
                .buttonStyle(.borderless)
                .disabled(isSummarizing || section.items.isEmpty)
                if isSummarizing { ProgressView().controlSize(.small) }
            }
            if let prose {
                Text(prose)
                    .font(.callout).textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardRaised.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            }
            if let proseError {
                Text(proseError).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    private func runSummarize() async {
        guard summarizeToken != nil else { return }   // skip the initial nil-id run
        guard answerer.isAvailable else {
            proseError = answerer.unavailableReason ?? "Summaries need Apple Intelligence, which isn't available."
            return
        }
        isSummarizing = true
        proseError = nil
        defer { isSummarizing = false }
        let bundle = ChatPromptBundle(prompt: ProjectActivityReport.phrasingPrompt(section: section),
                                      sources: [], requiresCitation: false)
        do {
            let answer = try await answerer.answer(request: ChatAnswerRequest(prompt: bundle))
            prose = answer.text
        } catch {
            proseError = (error as? LocalizedError)?.errorDescription ?? "Couldn't generate a summary."
        }
    }
}
