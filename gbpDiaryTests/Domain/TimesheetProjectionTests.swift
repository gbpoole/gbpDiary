import Foundation
import Testing
@testable import gbpDiary

// The Timesheet's report over the real models. The load-bearing assertion in almost every case is the
// INVARIANT — `rowsHours == ownHours` for every node — because that is what makes the page unable to show a
// number it cannot explain. Hours themselves stay `TimeLedger`'s business; these tests check that every one
// of them is accounted for by a row, and that nothing is silently dropped.
@MainActor
struct TimesheetProjectionTests {
    private let cal = Calendar(identifier: .gregorian)
    // 2024-01-03 Wed, 01-04 Thu, 01-06 Sat.
    private func at(_ day: Int, _ hour: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2024, month: 1, day: day, hour: hour))!
    }
    private func week() -> Range<Date> { at(1, 0)..<at(8, 0) }

    private func report(interval: Range<Date>? = nil, tasks: [Task] = [], conversations: [EmailConversation] = [],
                        meetings: [Minutes] = [], focusBlocks: [FocusBlock] = [], notes: [Note] = [],
                        projects: [Project] = []) -> TimesheetReport {
        TimesheetProjection.report(interval: interval, tasks: tasks, conversations: conversations,
                                   meetings: meetings, focusBlocks: focusBlocks, notes: notes,
                                   projects: projects, calendar: cal)
    }
    private func node(_ r: TimesheetReport, _ name: String) -> TimesheetNode? {
        r.allNodes.first { $0.name == name }
    }
    /// Every node's rows must account for exactly its hours.
    private func expectInvariant(_ r: TimesheetReport, sourceLocation: SourceLocation = #_sourceLocation) {
        for n in r.allNodes {
            #expect(abs(n.rowsHours - n.ownHours) < 0.0001,
                    "\(n.name): rows \(n.rowsHours) vs hours \(n.ownHours)", sourceLocation: sourceLocation)
        }
    }

    private func entry(_ date: Date, _ hours: Double, comment: String? = nil) -> TaskTimeEntry {
        let e = TaskTimeEntry(date: date, duration: Duration(value: hours, unit: .h))
        e.comment = comment
        return e
    }
    private func message(_ date: Date, _ direction: EmailDirection, subject: String = "Re: grant") -> EmailMessage {
        EmailMessage(messageId: UUID().uuidString, account: "a", mailbox: "INBOX", direction: direction,
                     fromAddress: "x@y.com", fromName: "X", subject: subject, date: date)
    }

    // MARK: the block net is work, not a residue

    // The headline complaint: hours were mostly focus-block capacity, and capacity produced no content at
    // all. A block's net now lands on its BACKING TASK's row, exactly like a logged entry.
    @Test func blockNet_becomesARowOnItsBackingTask() {
        let p = Project(name: "NODES")
        let task = Task(summary: "rebuild ingest"); task.project = p
        task.timeEntries = [entry(at(3, 10), 1, comment: "manifest v2")]
        let day = DayRecord(date: at(3))
        let block = FocusBlock(duration: Duration(value: 7.6, unit: .h), slot: .allDay)
        block.task = task; block.dayRecord = day

        let r = report(interval: week(), tasks: [task], focusBlocks: [block], projects: [p])
        let nodes = node(r, "NODES")
        #expect(nodes?.ownHours == 7.6)
        #expect(nodes?.rows.count == 1)                       // ONE row for the task, not a row per source
        let row = nodes?.rows.first
        #expect(row?.title == "rebuild ingest")
        #expect(row?.hours == 7.6)                            // 1h logged + 6.6h block net
        #expect(row?.details.map(\.text) == ["manifest v2", "Unspecified work"])
        #expect(row?.details.last?.hours == 6.6)
        expectInvariant(r)
    }

    // "Stack uncommented work into a single undefined block for each task."
    @Test func uncommentedTime_stacksIntoOneUnspecifiedLinePerTask() {
        let p = Project(name: "NODES")
        let task = Task(summary: "t"); task.project = p
        task.timeEntries = [entry(at(3, 9), 1), entry(at(4, 9), 2), entry(at(4, 14), 0.5, comment: "review")]

        let r = report(interval: week(), tasks: [task], projects: [p])
        let row = node(r, "NODES")?.rows.first
        #expect(row?.hours == 3.5)
        let unspecified = row?.details.filter(\.isUnspecified) ?? []
        #expect(unspecified.count == 1)                        // three uncommented hours → ONE line
        #expect(unspecified.first?.hours == 3)
        #expect(row?.details.filter { !$0.isUnspecified }.map(\.text) == ["review"])
        expectInvariant(r)
    }

    // A meeting or a conversation is already described by its own title, so it never carries the
    // "Unspecified work" line — found by running the report over the real store, where every meeting row
    // was reading "Meeting: X (1h) ↳ Unspecified work (1h)".
    @Test func meetingsAndConversations_doNotGetAnUnspecifiedWorkLine() {
        let p = Project(name: "NODES")
        let meeting = Minutes(meetingAt: at(3, 11)); meeting.projects = [p]; meeting.summary = "sync"
        meeting.duration = Duration(value: 1, unit: .h)
        let convo = EmailConversation(threadKey: "k"); convo.projects = [p]; convo.accept()
        convo.messages = [message(at(3, 15), .sent)]
        convo.timeEntries = [entry(at(3, 15), 0.25)]

        let r = report(interval: week(), conversations: [convo], meetings: [meeting], projects: [p])
        let rows = node(r, "NODES")?.rows ?? []
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.details.isEmpty })
        expectInvariant(r)       // details are informational; the hours still reconcile
    }

    @Test func describedFocusBlock_keepsItsCommentAsItsOwnLine() {
        let p = Project(name: "NODES")
        let task = Task(summary: "t"); task.project = p
        let day = DayRecord(date: at(3))
        let block = FocusBlock(duration: Duration(value: 4, unit: .h), slot: .allDay)
        block.task = task; block.dayRecord = day; block.comment = "paper figures"

        let r = report(interval: week(), tasks: [task], focusBlocks: [block], projects: [p])
        let row = node(r, "NODES")?.rows.first
        #expect(row?.details.map(\.text) == ["paper figures"])   // described → not stacked as unspecified
        #expect(row?.details.first?.hours == 4)
        expectInvariant(r)
    }

    // MARK: the invariant across mixed material

    @Test func invariant_holdsAcrossBlocksMeetingsTasksAndEmail() {
        let nodes = Project(name: "NODES"); let adacs = Project(name: "ADACS")
        let task = Task(summary: "ingest"); task.project = nodes
        task.timeEntries = [entry(at(3, 9), 1, comment: "parser")]
        let day = DayRecord(date: at(3))
        let block = FocusBlock(duration: Duration(value: 7.6, unit: .h), slot: .allDay)
        block.task = task; block.dayRecord = day
        let meeting = Minutes(meetingAt: at(3, 11)); meeting.projects = [adacs]
        meeting.duration = Duration(value: 1, unit: .h); meeting.summary = "data team sync"
        let convo = EmailConversation(threadKey: "k"); convo.projects = [adacs]; convo.accept()
        convo.messages = [message(at(3, 15), .sent)]
        convo.timeEntries = [entry(at(3, 15), 0.25)]

        let r = report(interval: week(), tasks: [task], conversations: [convo], meetings: [meeting],
                       focusBlocks: [block], projects: [nodes, adacs])
        expectInvariant(r)
        // The ADACS meeting AND the ADACS email time both sit inside the NODES block, so both reduce its net
        // (7.6 − 1 − 1 − 0.25 = 5.35) while counting against ADACS. NODES keeps its own logged hour on top.
        #expect(node(r, "NODES")?.ownHours == 6.35)
        #expect(node(r, "ADACS")?.ownHours == 1.25)
        #expect(node(r, "ADACS")?.rows.map(\.kind).contains(.meeting) == true)
        #expect(node(r, "ADACS")?.rows.map(\.kind).contains(.conversation) == true)
        #expect(node(r, "NODES")?.rows.map(\.kind) == [.task])
    }

    @Test func conversationRow_carriesTheSendReceiveBadgeForTheRange() {
        let p = Project(name: "NODES")
        let convo = EmailConversation(threadKey: "k"); convo.projects = [p]; convo.accept()
        convo.importance = .high
        convo.messages = [message(at(3, 9), .inbox), message(at(3, 15), .sent), message(at(30, 9), .inbox)]
        convo.timeEntries = [entry(at(3, 15), 0.5)]

        let r = report(interval: week(), conversations: [convo], projects: [p])
        let row = node(r, "NODES")?.rows.first
        #expect(row?.kind == .conversation)
        #expect(row?.badge == "1 sent · 1 recv [H]")   // the out-of-window message is not counted
        #expect(row?.hours == 0.5)
        expectInvariant(r)
    }

    // MARK: presence rows (0h by construction, so the invariant is safe)

    @Test func completedWithNothingLogged_isAZeroHourPresenceRow() {
        let p = Project(name: "NODES")
        let done = Task(summary: "tidy repo", status: .completed); done.project = p
        done.completedAt = at(4, 16)

        let r = report(interval: week(), tasks: [done], projects: [p])
        let n = node(r, "NODES")
        #expect(n?.ownHours == 0)
        #expect(n?.rows.isEmpty == true)
        #expect(n?.unloggedRows.map(\.kind) == [.completedNoTime])
        #expect(n?.unloggedRows.first?.hours == 0)
        #expect(n?.unloggedRows.first?.title == "tidy repo")
        expectInvariant(r)
    }

    // A project whose only evidence is an uncredited completion must still get a section — the old report
    // filtered on `hours > 0` and the project vanished.
    @Test func projectWithOnlyUncreditedCompletions_stillAppears() {
        let p = Project(name: "NODES")
        let done = Task(summary: "x", status: .completed); done.project = p; done.completedAt = at(4)
        let r = report(interval: week(), tasks: [done], projects: [p])
        #expect(node(r, "NODES") != nil)
    }

    @Test func completedTaskWithLoggedTime_isOneRowNotTwo() {
        let p = Project(name: "NODES")
        let done = Task(summary: "x", status: .completed); done.project = p
        done.completedAt = at(4, 16)
        done.timeEntries = [entry(at(4, 9), 2)]

        let r = report(interval: week(), tasks: [done], projects: [p])
        let n = node(r, "NODES")
        #expect(n?.rows.count == 1)
        #expect(n?.unloggedRows.isEmpty == true)        // not duplicated as a "no time logged" row
        #expect(n?.rows.first?.status?.hasPrefix("✓") == true)
        expectInvariant(r)
    }

    // MARK: nothing is silently deleted

    // The old report removed the "(no project)" bucket by name, so these hours disappeared from the page
    // AND from its headline.
    @Test func unattributedTime_isReported_notDeleted() {
        let orphan = Task(summary: "misc")                       // no project
        orphan.timeEntries = [entry(at(3, 9), 2)]
        let r = report(interval: week(), tasks: [orphan])
        let n = r.nodes.last
        #expect(n?.isUnattributed == true)
        #expect(n?.ownHours == 2)
        #expect(n?.rows.first?.title == "misc")
        #expect(r.totalOwnHours == 2)
        expectInvariant(r)
    }

    @Test func unattributedNode_isAlwaysLast() {
        let p = Project(name: "NODES")
        let task = Task(summary: "t"); task.project = p; task.timeEntries = [entry(at(3), 1)]
        let orphan = Task(summary: "misc"); orphan.timeEntries = [entry(at(3), 9)]   // more hours
        let r = report(interval: week(), tasks: [task, orphan], projects: [p])
        #expect(r.nodes.last?.isUnattributed == true)            // despite ranking first by hours
        #expect(r.nodes.first?.name == "NODES")
    }

    @Test func unfiledConversation_isListedUnderUnattributed_unlessDismissed() {
        let unfiled = EmailConversation(threadKey: "a")
        unfiled.messages = [message(at(3, 9), .inbox, subject: "Re: unfiled thing")]
        let spam = EmailConversation(threadKey: "b")
        spam.messages = [message(at(3, 9), .inbox, subject: "buy now")]
        spam.triageDismiss()

        let r = report(interval: week(), conversations: [unfiled, spam])
        let n = r.nodes.last
        #expect(n?.isUnattributed == true)
        #expect(n?.unloggedRows.map(\.kind) == [.unfiledConversation])
        #expect(n?.unloggedRows.first?.title == "unfiled thing")   // Re: stripped
        expectInvariant(r)
    }

    // A dismissed conversation you logged time against is still real work: dropping the row would break the
    // invariant, so it is accounted for even though unfiled chatter is not listed.
    @Test func dismissedConversationWithLoggedTime_isStillAccountedFor() {
        let p = Project(name: "NODES")
        let convo = EmailConversation(threadKey: "k"); convo.projects = [p]; convo.triageDismiss()
        convo.messages = [message(at(3, 9), .inbox)]
        convo.timeEntries = [entry(at(3, 10), 0.5)]
        let r = report(interval: week(), conversations: [convo], projects: [p])
        #expect(node(r, "NODES")?.ownHours == 0.5)
        expectInvariant(r)
    }

    // MARK: hierarchy

    @Test func subprojectTime_nestsUnderItsParent_whichKeepsItsOwnHoursSeparate() {
        let parent = Project(name: "Pawsey")
        let child = Project(name: "Ingest"); child.parent = parent
        let parentTask = Task(summary: "admin"); parentTask.project = parent
        parentTask.timeEntries = [entry(at(3), 1)]
        let childTask = Task(summary: "rebuild"); childTask.project = child
        childTask.timeEntries = [entry(at(3), 6)]

        let r = report(interval: week(), tasks: [parentTask, childTask], projects: [parent, child])
        #expect(r.nodes.count == 1)                       // one root
        let root = r.nodes[0]
        #expect(root.name == "Pawsey")
        #expect(root.ownHours == 1)                       // own work only
        #expect(root.subtreeHours == 7)                   // plus the subproject
        #expect(root.children.map(\.name) == ["Ingest"])
        #expect(root.children.first?.ownHours == 6)
        expectInvariant(r)
    }

    // A parent that logged nothing itself must still appear, or its subproject has nowhere to nest.
    @Test func parentWithNoTimeOfItsOwn_stillAnchorsItsSubproject() {
        let parent = Project(name: "Pawsey")
        let child = Project(name: "Ingest"); child.parent = parent
        let task = Task(summary: "rebuild"); task.project = child
        task.timeEntries = [entry(at(3), 6)]

        let r = report(interval: week(), tasks: [task], projects: [parent, child])
        #expect(r.nodes.map(\.name) == ["Pawsey"])
        #expect(r.nodes[0].ownHours == 0)
        #expect(r.nodes[0].subtreeHours == 6)
        expectInvariant(r)
    }

    // Keying on `Project.id` rather than the name: two same-named subprojects are two sections.
    @Test func duplicateProjectNames_doNotCollide() {
        let a = Project(name: "Ingest"); let b = Project(name: "Ingest")
        let ta = Task(summary: "a"); ta.project = a; ta.timeEntries = [entry(at(3), 1)]
        let tb = Task(summary: "b"); tb.project = b; tb.timeEntries = [entry(at(3), 2)]

        let r = report(interval: week(), tasks: [ta, tb], projects: [a, b])
        #expect(r.nodes.count == 2)
        #expect(r.nodes.map(\.ownHours).sorted() == [1, 2])
        expectInvariant(r)
    }

    // MARK: window

    @Test func outOfWindowWork_isExcluded() {
        let p = Project(name: "NODES")
        let task = Task(summary: "t"); task.project = p
        task.timeEntries = [entry(at(3), 1), entry(at(30), 5)]   // 30 Jan is outside the week
        let r = report(interval: week(), tasks: [task], projects: [p])
        #expect(node(r, "NODES")?.ownHours == 1)
        expectInvariant(r)
    }

    // Weekend work books back to Friday (the ledger folds it); the row must land in the same window as the
    // hours, or the rows and the figures would disagree at a week boundary.
    @Test func weekendWork_isReportedInTheWeekItFoldsInto() {
        let p = Project(name: "NODES")
        let task = Task(summary: "t"); task.project = p
        task.timeEntries = [entry(at(6, 11), 3)]            // Saturday 6 Jan → Friday 5 Jan
        let r = report(interval: week(), tasks: [task], projects: [p])
        #expect(node(r, "NODES")?.ownHours == 3)
        #expect(node(r, "NODES")?.rows.first?.date == cal.startOfDay(for: at(5)))
        expectInvariant(r)
    }

    // MARK: mined prose

    @Test func extracts_comeFromExplicitlyLinkedNotesAndMinutesOnly() {
        let p = Project(name: "NODES")
        let meeting = Minutes(meetingAt: at(3, 11)); meeting.projects = [p]; meeting.summary = "sync"
        let minutesNote = Note(content: "## Agreed\n- manifest **v2** by Friday", title: "")
        minutesNote.minutes = meeting
        meeting.note = minutesNote
        let projectNote = Note(content: "Wrote up the parser design.", title: "Design")
        projectNote.project = p; projectNote.updatedAt = at(4)
        let loose = Note(content: "unrelated", title: "Loose")      // no project → never mined
        loose.updatedAt = at(4)

        let r = report(interval: week(), meetings: [meeting], notes: [minutesNote, projectNote, loose],
                       projects: [p])
        let titles = node(r, "NODES")?.extracts.map(\.title) ?? []
        #expect(titles.contains("Minutes: sync"))
        #expect(titles.contains("Note: Design"))
        #expect(!titles.contains { $0.contains("Loose") })
        #expect(titles.count == 2)                                  // the minutes note is not counted twice
        // Markdown is stripped so the prose prompt gets readable text, not syntax.
        let minutesText = node(r, "NODES")?.extracts.first { $0.title == "Minutes: sync" }?.text ?? ""
        #expect(minutesText.contains("manifest v2 by Friday"))
        #expect(!minutesText.contains("##"))
        #expect(!minutesText.contains("**"))
    }

    @Test func extractText_isBounded() {
        let p = Project(name: "NODES")
        let note = Note(content: String(repeating: "word ", count: 500), title: "Long")
        note.project = p; note.updatedAt = at(4)
        let r = TimesheetProjection.report(interval: week(), tasks: [], conversations: [], meetings: [],
                                           focusBlocks: [], notes: [note], projects: [p], calendar: cal,
                                           maxExtractCharacters: 50)
        let text = node(r, "NODES")?.extracts.first?.text ?? ""
        #expect(text.count <= 51)            // the cap plus the ellipsis
        #expect(text.hasSuffix("…"))
    }

    @Test func emptyStore_isAnEmptyReport() {
        #expect(report(interval: week()).isEmpty)
    }
}
