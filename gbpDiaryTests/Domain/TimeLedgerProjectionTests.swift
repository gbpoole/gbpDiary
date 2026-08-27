import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct TimeLedgerProjectionTests {
    private let cal = Calendar(identifier: .gregorian)
    // 2024-01-03 Wed, 01-06 Sat.
    private func at(_ day: Int, _ hour: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2024, month: 1, day: day, hour: hour))!
    }
    private func hours(_ r: LedgerResult, _ name: String) -> Double? { r.perProject.first { $0.name == name }?.hours }

    // The reported bug, end-to-end through the projector: a 3h NODES block containing a 1h ADACS meeting.
    @Test func inBlockMeeting_attributedToOwnProject_reducesBlockNet() {
        let nodes = Project(name: "NODES"); let adacs = Project(name: "ADACS")
        let day = DayRecord(date: at(3))
        let block = FocusBlock(duration: Duration(value: 3, unit: .h), slot: .allDay)
        block.project = nodes; block.dayRecord = day
        let meeting = Minutes(meetingAt: at(3, 10)); meeting.projects = [adacs]; meeting.duration = Duration(value: 1, unit: .h)

        let r = TimeLedgerProjection.ledger(focusBlocks: [block], tasks: [], conversations: [], meetings: [meeting], calendar: cal)
        #expect(hours(r, "NODES") == 2)
        #expect(hours(r, "ADACS") == 1)
        #expect(r.blockNet[block.id] == 2)
        #expect(r.standardTotal == 3)
    }

    @Test func standaloneTaskEntry_countedOnADayWithNoBlocks() {
        let p = Project(name: "Alpha")
        let task = Task(summary: "t"); task.project = p
        task.timeEntries = [TaskTimeEntry(date: at(3, 11), duration: Duration(value: 1, unit: .h))]
        let r = TimeLedgerProjection.ledger(focusBlocks: [], tasks: [task], conversations: [], meetings: [], calendar: cal)
        #expect(hours(r, "Alpha") == 1)
        #expect(r.standardTotal == 1)
    }

    @Test func legacyCompletedTaskDuration_counted() {
        let p = Project(name: "Beta")
        let task = Task(summary: "done"); task.project = p
        task.completedAt = at(3); task.duration = Duration(value: 2, unit: .h)
        let r = TimeLedgerProjection.ledger(focusBlocks: [], tasks: [task], conversations: [], meetings: [], calendar: cal)
        #expect(hours(r, "Beta") == 2)
        #expect(r.standardTotal == 2)
    }

    @Test func weekendWork_foldsToFridayAndIsOvertime() {
        let p = Project(name: "Gamma")
        let task = Task(summary: "sat"); task.project = p
        task.timeEntries = [TaskTimeEntry(date: at(6, 11), duration: Duration(value: 2, unit: .h))]   // Saturday
        let r = TimeLedgerProjection.ledger(focusBlocks: [], tasks: [task], conversations: [], meetings: [], calendar: cal)
        #expect(hours(r, "Gamma") == 2)
        #expect(r.overtime == 2)
        #expect(r.standardTotal == 0)
    }

    // A conversation OWNS its logged time, attributed to the conversation's project(s) at each entry's
    // date; in-block conversation time reduces that block's net (like an in-block activity).
    @Test func inBlockConversationTime_attributedToOwnProject_reducesBlockNet() {
        let nodes = Project(name: "NODES"); let admin = Project(name: "Admin")
        let day = DayRecord(date: at(3))
        let block = FocusBlock(duration: Duration(value: 3, unit: .h), slot: .allDay)
        block.project = nodes; block.dayRecord = day
        let convo = EmailConversation(threadKey: "t"); convo.projects = [admin]
        convo.timeEntries = [TaskTimeEntry(date: at(3, 10), duration: Duration(value: 1, unit: .h))]

        let r = TimeLedgerProjection.ledger(focusBlocks: [block], tasks: [], conversations: [convo],
                                            meetings: [], calendar: cal)
        #expect(hours(r, "NODES") == 2)
        #expect(hours(r, "Admin") == 1)
        #expect(r.blockNet[block.id] == 2)
        #expect(r.standardTotal == 3)
    }

    @Test func standaloneConversationTime_countedToProjectAndStandardTotal() {
        let p = Project(name: "Zeta")
        let convo = EmailConversation(threadKey: "t"); convo.projects = [p]
        convo.timeEntries = [TaskTimeEntry(date: at(3, 11), duration: Duration(value: 1.5, unit: .h))]
        let r = TimeLedgerProjection.ledger(focusBlocks: [], tasks: [], conversations: [convo],
                                            meetings: [], calendar: cal)
        #expect(hours(r, "Zeta") == 1.5)
        #expect(r.standardTotal == 1.5)
    }

    // A sent email's logged time must reach the Chat/Timesheet ledger. It counts when carried by the
    // conversation (as SentEmailActivityRow now logs it); a stray per-message email-only entry is invisible
    // to the task-shaped ledger path — which is exactly why the row logs against the conversation.
    @Test func sentEmailTime_countsViaConversation_notViaPerMessageEmail() {
        let p = Project(name: "Kappa")
        let convo = EmailConversation(threadKey: "t"); convo.projects = [p]
        let sent = EmailMessage(messageId: "m", account: "a", mailbox: "Sent", direction: .sent,
                                fromAddress: "x@y.com", fromName: nil, subject: "re: x", date: at(3, 11))
        convo.messages = [sent]; sent.conversation = convo

        // As SentEmailActivityRow now logs it — against the conversation.
        convo.timeEntries = [TaskTimeEntry(date: at(3, 11), duration: Duration(value: 0.5, unit: .h))]
        let counted = TimeLedgerProjection.ledger(focusBlocks: [], tasks: [], conversations: [convo],
                                                  meetings: [], calendar: cal)
        #expect(hours(counted, "Kappa") == 0.5)

        // A stray per-message email-only entry (the old behaviour) never reaches the task-shaped path.
        convo.timeEntries = []
        let legacy = TaskTimeEntry(date: at(3, 11), duration: Duration(value: 0.5, unit: .h))
        legacy.email = sent
        sent.timeEntries = [legacy]
        let notCounted = TimeLedgerProjection.ledger(focusBlocks: [], tasks: [], conversations: [convo],
                                                     meetings: [], calendar: cal)
        #expect(hours(notCounted, "Kappa") == nil)
    }

    @Test func standaloneMeeting_countedInStandardTotal() {
        let p = Project(name: "Delta")
        let m = Minutes(meetingAt: at(3, 14)); m.projects = [p]; m.duration = Duration(value: 1, unit: .h)
        let r = TimeLedgerProjection.ledger(focusBlocks: [], tasks: [], conversations: [], meetings: [m], calendar: cal)
        #expect(hours(r, "Delta") == 1)
        #expect(r.standardTotal == 1)
    }
}
