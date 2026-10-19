import SwiftUI
import SwiftData

struct TimesheetView: View {
    @Query(sort: \Task.completedAt, order: .reverse) private var allTasks: [Task]
    @Query(sort: \Project.name) private var projects: [Project]
    @Query private var allFocusBlocks: [FocusBlock]
    @Query private var allConversations: [EmailConversation]
    @Query private var allEmails: [EmailMessage]   // for source navigation (open a message in Mail)
    @Query private var allMeetings: [Minutes]
    @Query private var allNotes: [Note]
    @Query private var storedSummaries: [TimesheetSummary]

    @Environment(WorkspaceModel.self) private var workspace
    @State private var mailService = MailScriptService()
    @State private var selectedTask: Task?
    @State private var exportError: String?
    @State private var copiedMarkdown = false
    @State private var bodyRun: TimesheetBodyRun?
    @State private var pendingTree: PendingTree?

    /// `sheet(item:)` needs an Identifiable value; the run itself is a reference type.
    private struct RunBox: Identifiable {
        let run: TimesheetBodyRun
        var id: Int { ObjectIdentifier(run).hashValue }
    }

    /// The tree waiting on its email bodies, held while the progress sheet runs.
    private struct PendingTree {
        let content: TimesheetExportSnapshot.FullContent
        let url: URL
    }
    private let answerer = FoundationModelsChatAnswerer()

    @State private var selectedRange: TimesheetRange = .thisWeek
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var customEnd: Date = Date()

    private var rangeInterval: DateInterval {
        TimesheetComputation.rangeInterval(
            selectedRange: selectedRange,
            customStart: customStart,
            customEnd: customEnd
        )
    }

    private var interval: Range<Date> { rangeInterval.start..<rangeInterval.end }

    // The canonical hours. The headline is the ledger's own grandTotal — the same figure the diary shows for
    // the same days — so the two pages can never contradict each other.
    private var ledger: LedgerResult {
        TimeLedgerProjection.ledger(focusBlocks: allFocusBlocks, tasks: allTasks,
                                    conversations: allConversations, meetings: allMeetings,
                                    interval: interval)
    }

    // Per-project hours paired with the rows that account for them (and the mined prose). One assembler,
    // shared with Chat's time-report lens.
    private var report: TimesheetReport {
        TimesheetFilter.apply(unfilteredReport, selected: selectedProjectIDs)
    }

    private var unfilteredReport: TimesheetReport {
        TimesheetProjection.report(interval: interval, tasks: allTasks, conversations: allConversations,
                                   meetings: allMeetings, focusBlocks: allFocusBlocks,
                                   notes: allNotes, projects: projects)
    }

    /// The project filter lives on the page's persisted `ListPageFilter`, like every other list page's, so
    /// it survives tab switches and relaunches. Ids are stored as `project.<uuid>`.
    private var filterState: ListPageFilter { workspace.pageFilter(for: .timesheet) }

    private var selectedProjectIDs: Set<UUID> {
        Set(filterState.activeFilterIds.compactMap { id in
            id.hasPrefix("project.") ? UUID(uuidString: String(id.dropFirst("project.".count))) : nil
        })
    }

    private var selectedProjects: [Project] {
        let ids = selectedProjectIDs
        return projects.filter { ids.contains($0.id) }
    }

    private func setSelectedProjects(_ chosen: [Project]) {
        filterState.activeFilterIds = Set(chosen.map { "project.\($0.id.uuidString)" })
    }

    /// The cached prose for this period, by node. Written by `TimesheetSummaryDriver`, read here.
    private var proseByNode: [UUID: String] {
        let period = interval
        var map: [UUID: String] = [:]
        for summary in storedSummaries
        where summary.rangeStart == period.lowerBound && summary.rangeEnd == period.upperBound {
            if summary.state == .done, let text = summary.text, !text.isEmpty { map[summary.nodeID] = text }
        }
        return map
    }

    var body: some View {
        let ledger = ledger
        let report = report
        let prose = proseByNode
        return VStack(spacing: 0) {
            rangeBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    totalCard(ledger: ledger, report: report)
                    projectBreakdown(report: report, prose: prose)
                }
                .padding()
            }
            // Fills each project's paragraph in the background for the period on screen.
            TimesheetSummaryDriver(nodes: report.allNodes, interval: interval)
        }
        .onAppear { answerer.prewarm() }   // warm the on-device model ahead of the first summary
        .onChange(of: selectedRange) { copiedMarkdown = false }
        .sheet(item: $selectedTask) { task in
            TaskEditorSheet(task: task, defaultDate: task.completedAt ?? Date())
        }
        .sheet(item: Binding(get: { bodyRun.map { RunBox(run: $0) } },
                             set: { if $0 == nil { bodyRun = nil } })) { box in
            TimesheetExportProgressSheet(run: box.run, mailService: mailService) { outcomes in
                if let pending = pendingTree { writeTree(content: pending.content, bodies: outcomes, to: pending.url) }
                pendingTree = nil
                bodyRun = nil
            }
        }
        .alert("Couldn't export", isPresented: .constant(exportError != nil)) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private var rangeBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Range", selection: $selectedRange) {
                ForEach(TimesheetRange.allCases, id: \.self) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                if selectedRange == .custom {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, displayedComponents: .date)
                }
                Text(TimesheetExport.periodLabel(interval))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider().frame(height: 14)
                // Narrows the page AND everything it exports. Selecting a project takes its subprojects.
                FuzzyPickerField(
                    allItems: projects,
                    selected: Binding(get: { selectedProjects }, set: { setSelectedProjects($0) }),
                    label: \.name,
                    chipColor: AppTheme.project,
                    placeholder: "Search projects…",
                    tapArea: true,
                    emptyLabel: "All projects"
                )
                .frame(maxWidth: 320)
                Spacer()
                Button {
                    copyMarkdown()
                } label: {
                    Label(copiedMarkdown ? "Copied" : "Copy as Markdown",
                          systemImage: copiedMarkdown ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                #if os(macOS)
                Menu {
                    Button("Report…") { exportMarkdown(fullContent: false, bodies: false) }
                    Button("Full content…") { exportMarkdown(fullContent: true, bodies: false) }
                    Button("Full content with email bodies…") { exportMarkdown(fullContent: true, bodies: true) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                #endif
            }
            .labelsHidden()
        }
        .padding()
    }

    private var markdown: String {
        TimesheetExport.composeMarkdown(report: report, ledger: ledger,
                                        periodLabel: TimesheetExport.periodLabel(interval),
                                        prose: proseByNode)
    }

    private func copyMarkdown() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        #endif
        copiedMarkdown = true
    }

    #if os(macOS)
    // The export is a FOLDER containing summary.md + data.json (+ content/ for a full export).
    //
    // It has to be: NSSavePanel grants the sandbox access to exactly the URL you name, so writing a
    // sibling file or creating a sibling directory is refused — which is what happened the first time this
    // ran (the .md saved, the .json was denied). Naming a folder puts every artefact under the one granted
    // URL. It also gives an agent a predictable shape: point it at the folder and the names are fixed.
    //
    // `fullContent` adds the markdown tree an agent can read directly; `bodies` additionally reads each
    // relevant message's body from local Mail at export time (serial, slow, shown in a progress sheet) and
    // writes it into that tree ONLY — never into data.json, which is what an external reader picks up.
    private func exportMarkdown(fullContent: Bool, bodies: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = TimesheetExport.folderName(
            periodLabel: TimesheetExport.periodLabel(interval))
        panel.nameFieldLabel = "Export folder:"
        panel.message = "Choose where to create the export folder."
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let treeURL = folder.appendingPathComponent(TimesheetExport.contentDirectoryName, isDirectory: true)
        let jsonURL = folder.appendingPathComponent(TimesheetExport.dataFileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // The fast path first, so it survives whatever the body fetch does.
            try TimesheetExport.composeMarkdown(
                report: report, ledger: ledger, periodLabel: TimesheetExport.periodLabel(interval),
                prose: proseByNode,
                contentDirectory: fullContent ? TimesheetExport.contentDirectoryName : nil)
                .write(to: folder.appendingPathComponent(TimesheetExport.summaryFileName),
                       atomically: true, encoding: .utf8)
            try TimesheetDataExport.write(dataSnapshot(fullContent: fullContent), to: jsonURL)
            AppSettingsStore.lastTimesheetExportPath = jsonURL.path
        } catch {
            exportError = error.localizedDescription
            return
        }
        guard fullContent else { return }

        let content = TimesheetFilter.apply(
            TimesheetContentProjection.build(interval: interval, meetings: allMeetings,
                                             notes: allNotes, conversations: allConversations),
            projectNames: TimesheetFilter.projectNames(in: unfilteredReport, selected: selectedProjectIDs))
        guard bodies else {
            writeTree(content: content, bodies: [:], to: treeURL)
            return
        }
        let resolved = TimesheetBodyPlanProjection.resolve(content: content,
                                                           conversations: allConversations,
                                                           emails: allEmails)
        guard !resolved.messages.isEmpty else {
            writeTree(content: content, bodies: resolved.plan.skipped, to: treeURL)
            return
        }
        pendingTree = PendingTree(content: content, url: treeURL)
        bodyRun = TimesheetBodyRun(messages: resolved.messages, preSkipped: resolved.plan.skipped)
    }

    private func writeTree(content: TimesheetExportSnapshot.FullContent,
                           bodies: [UUID: TimesheetEmailBody], to url: URL) {
        do {
            let files = TimesheetContentTree.compose(
                content: content, periodLabel: TimesheetExport.periodLabel(interval), bodies: bodies)
            try TimesheetContentTreeWriter.write(files, to: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
    #endif

    private func dataSnapshot(fullContent: Bool) -> TimesheetExportSnapshot {
        TimesheetDataExport.snapshot(
            report: report, ledger: ledger, interval: interval,
            periodLabel: TimesheetExport.periodLabel(interval), prose: proseByNode,
            content: fullContent ? TimesheetContentProjection.build(
                interval: interval, meetings: allMeetings, notes: allNotes,
                conversations: allConversations) : nil)
    }

    private func totalCard(ledger: LedgerResult, report: TimesheetReport) -> some View {
        // Over-logging (more activity inside a block than its capacity) legitimately makes the rows sum
        // higher than the diary's total. Name the difference rather than quietly showing one or the other.
        let overLogged = report.totalOwnHours - ledger.grandTotal
        return GroupBox("Total") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    // Filtered, the headline is the selected projects' own hours — otherwise it would
                    // report a period total for work the page isn't showing.
                    let filtered = !selectedProjectIDs.isEmpty
                    let headline = filtered ? report.totalOwnHours : ledger.grandTotal
                    Text(TimeFormat.hours(headline))
                        .font(.largeTitle.bold())
                    Text("\(TimeFormat.days(headline))  ·  \(Self.countsLine(report))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if filtered {
                        Text("\(selectedProjects.count) project\(selectedProjects.count == 1 ? "" : "s")"
                             + " · of \(TimeFormat.hours(ledger.grandTotal)) in this period")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if ledger.overtime > 0 {
                        Text("Includes \(TimeFormat.hours(ledger.overtime)) overtime")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if overLogged > 0.05, selectedProjectIDs.isEmpty {
                        Text("+\(TimeFormat.hours(overLogged)) over-logged — activity inside focus blocks exceeds their capacity")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
        }
    }

    private func projectBreakdown(report: TimesheetReport, prose: [UUID: String]) -> some View {
        GroupBox("By Project") {
            if report.isEmpty {
                Text("No logged time in this range.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(report.nodes.enumerated()), id: \.element.id) { index, node in
                        TimesheetNodeView(node: node, depth: 0, totalHours: report.totalOwnHours,
                                          prose: prose, onOpen: open)
                        if index < report.nodes.count - 1 { Divider().padding(.vertical, 2) }
                    }
                }
            }
        }
    }

    private static func countsLine(_ report: TimesheetReport) -> String {
        let rows = report.allNodes.flatMap { $0.rows + $0.unloggedRows }
        func count(_ kinds: Set<TimesheetRowKind>) -> Int {
            Set(rows.filter { kinds.contains($0.kind) }.map(\.id)).count
        }
        let tasks = count([.task, .completedNoTime])
        let meetings = count([.meeting])
        let convos = count([.conversation, .unfiledConversation])
        return "\(tasks) tasks · \(meetings) meetings · \(convos) conversations"
    }

    // Navigate a row or extract to its source.
    private func open(_ source: ChatSourceReference) {
        switch source.navigationKind {
        case .meeting:
            if let m = allMeetings.first(where: { $0.id == source.navigationID }) {
                workspace.focusOrOpen(.minutes(m.persistentModelID))
            }
        case .task:
            if let t = allTasks.first(where: { $0.id == source.navigationID }) {
                workspace.focusOrOpen(.task(t.persistentModelID))
            }
        case .email:
            if let e = allEmails.first(where: { $0.id == source.navigationID }) {
                mailService.openMessage(e) { _ in }
            }
        case .note:
            if let n = allNotes.first(where: { $0.id == source.navigationID }) {
                workspace.reveal(note: n)
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

// One project (and, nested inside it, its subprojects). The header carries the time figures; the prose
// summarises the whole subtree; the rows that ACCOUNT for the hours sit behind a disclosure, collapsed by
// default, each detail clipped to one line (the markdown export carries them in full).
private struct TimesheetNodeView: View {
    let node: TimesheetNode
    let depth: Int
    let totalHours: Double
    let prose: [UUID: String]
    let onOpen: (ChatSourceReference) -> Void

    @State private var showRows = false

    private var percent: Int { totalHours > 0 ? Int((node.ownHours / totalHours * 100).rounded()) : 0 }
    private var paragraph: String? { prose[node.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            if let paragraph {
                Text(paragraph)
                    .font(.callout).textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardRaised.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            } else if !node.subtreeRows.isEmpty {
                // The driver fills this in the background; the rows below are the answer until it does.
                Text("Summarising…").font(.caption).foregroundStyle(.tertiary)
            }
            controls
            if showRows { evidence }
            ForEach(node.children) { child in
                TimesheetNodeView(node: child, depth: depth + 1, totalHours: totalHours,
                                  prose: prose, onOpen: onOpen)
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, CGFloat(depth) * 16)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(node.name)
                .font(depth == 0 ? .headline : .subheadline.weight(.semibold))
                .foregroundStyle(node.isUnattributed ? .orange : .primary)
            Spacer()
            Text(TimeFormat.hours(node.ownHours)).monospacedDigit()
            Text("·").foregroundStyle(.secondary)
            Text(TimeFormat.days(node.ownHours)).foregroundStyle(.secondary).monospacedDigit()
            Text("·").foregroundStyle(.secondary)
            Text(ChatTimeTotals.weeksText(node.distinctWeeks)).foregroundStyle(.secondary)
            Text("(\(percent)%)").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if !node.children.isEmpty {
                Text("subtree \(TimeFormat.hours(node.subtreeHours))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                showRows.toggle()
            } label: {
                Label(showRows ? "Hide detail" : "Detail (\(node.rows.count + node.unloggedRows.count))",
                      systemImage: showRows ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(!node.hasContent)
            Spacer()
        }
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(node.groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title.uppercased())
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(group.rows) { row in rowView(row) }
                }
            }
            if !node.extracts.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NOTES").font(.caption2).foregroundStyle(.secondary)
                    ForEach(node.extracts) { extract in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(extract.title).font(.caption.weight(.semibold))
                            Text(extract.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if let s = extract.source { onOpen(s) } }
                    }
                }
            }
        }
        .padding(.top, 4)
        .padding(.leading, 4)
    }

    private func rowView(_ row: TimesheetRow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                Text(row.title)
                    .foregroundStyle(row.source != nil ? Color.accentColor : .primary)
                if let status = row.status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                if let badge = row.badge {
                    Text(badge).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if row.hours > 0 {
                    Text(TimeFormat.hours(row.hours)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .contentShape(Rectangle())
            .onTapGesture { if let s = row.source { onOpen(s) } }
            ForEach(row.details) { detail in
                Text("↳ \(detail.label)")
                    .font(.caption)
                    .foregroundStyle(detail.isUnspecified ? .tertiary : .secondary)
                    .lineLimit(1)
                    .padding(.leading, 14)
            }
        }
    }
}
