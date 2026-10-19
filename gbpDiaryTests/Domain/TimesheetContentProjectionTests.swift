import Foundation
import Testing
@testable import gbpDiary

// The full-content bundle an agent works from. The load-bearing properties: it carries COMPLETE text (not
// the report's clipped extracts), it windows exactly like the report (or it would describe a different
// period than the figures beside it), and it contains no email body — because none exists to contain.
@MainActor
struct TimesheetContentProjectionTests {
    private let cal = Calendar(identifier: .gregorian)
    // 2026-01-05 Mon … 2026-01-09 Fri, 01-10 Sat.
    private func at(_ day: Int, _ hour: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }
    private func week() -> Range<Date> { at(5, 0)..<at(10, 0) }

    private func build(meetings: [Minutes] = [], notes: [Note] = [],
                       conversations: [EmailConversation] = [],
                       interval: Range<Date>? = nil) -> TimesheetExportSnapshot.FullContent {
        TimesheetContentProjection.build(interval: interval ?? week(), meetings: meetings, notes: notes,
                                         conversations: conversations, calendar: cal)
    }
    private func message(_ date: Date, _ direction: EmailDirection, subject: String = "Re: grant",
                         summary: String? = nil) -> EmailMessage {
        let m = EmailMessage(messageId: UUID().uuidString, account: "a", mailbox: "INBOX",
                             direction: direction, fromAddress: "x@y.com", fromName: "X",
                             subject: subject, date: date)
        m.summary = summary
        return m
    }

    @Test func meetingsCarryTheirCompleteMinutes() {
        let project = Project(name: "NODES")
        let person = Person(name: "Asher")
        let meeting = Minutes(meetingAt: at(6, 11))
        meeting.summary = "Requirements gathering"
        meeting.duration = Duration(value: 1, unit: .h)
        meeting.projects = [project]
        meeting.attendees = [person]
        let body = String(repeating: "Discussed the manifest in detail. ", count: 60)   // > any extract cap
        let note = Note(content: body)
        note.minutes = meeting
        meeting.note = note

        let content = build(meetings: [meeting], notes: [note])
        #expect(content.meetings.count == 1)
        let exported = content.meetings[0]
        #expect(exported.summary == "Requirements gathering")
        #expect(exported.durationHours == 1)
        #expect(exported.projects == ["NODES"])
        #expect(exported.attendees == ["Asher"])
        #expect(exported.minutesMarkdown == body)        // complete, not clipped
        #expect(content.notes.isEmpty)                   // not duplicated as a standalone note
    }

    @Test func legacyMinutesContentIsCarriedWhenThereIsNoNote() {
        let meeting = Minutes(meetingAt: at(6))
        meeting.minutesContent = "old plain-text minutes"
        #expect(build(meetings: [meeting]).meetings[0].minutesMarkdown == "old plain-text minutes")
    }

    @Test func notesCarryFullMarkdownWithTheirContext() {
        let project = Project(name: "NODES")
        let note = Note(content: "# Design\n\nThe parser rewrite.", title: "Parser design")
        note.project = project
        note.updatedAt = at(7)

        let content = build(notes: [note])
        #expect(content.notes.count == 1)
        #expect(content.notes[0].title == "Parser design")
        #expect(content.notes[0].project == "NODES")
        #expect(content.notes[0].markdown == "# Design\n\nThe parser rewrite.")
    }

    @Test func emptyNotesAreSkipped() {
        let note = Note(content: "", title: "Empty")
        note.updatedAt = at(7)
        #expect(build(notes: [note]).notes.isEmpty)
    }

    // No body field exists on the message type at all; the summary is what the app has.
    @Test func conversationsCarrySubjectsAndOnDeviceSummariesOnly() {
        let project = Project(name: "NODES")
        let convo = EmailConversation(threadKey: "k")
        convo.projects = [project]
        convo.accept()
        convo.importance = .high
        convo.messages = [message(at(6, 9), .inbox, summary: "They asked for the quota."),
                          message(at(6, 15), .sent, summary: "You confirmed the quota.")]
        convo.timeEntries = [TaskTimeEntry(date: at(6, 16), duration: Duration(value: 0.5, unit: .h))]

        let content = build(conversations: [convo])
        #expect(content.conversations.count == 1)
        let exported = content.conversations[0]
        #expect(exported.projects == ["NODES"])
        #expect(exported.importance == "high")
        #expect(exported.loggedHours == 0.5)
        #expect(exported.messages.map(\.direction) == ["inbox", "sent"])     // oldest first
        #expect(exported.messages.map(\.summary) == ["They asked for the quota.",
                                                     "You confirmed the quota."])
        // The projection itself still carries no body — that part of the promise is permanent. The
        // notice now also names the opt-in markdown tree, which is the only place bodies can land.
        #expect(content.notice.contains("THIS JSON contains no email bodies"))
        #expect(content.notice.contains("the app never stores one"))
        #expect(content.notice.contains("_content directory"))
    }

    @Test func dismissedConversationsAreExcluded() {
        let convo = EmailConversation(threadKey: "spam")
        convo.messages = [message(at(6), .inbox)]
        convo.triageDismiss()
        #expect(build(conversations: [convo]).conversations.isEmpty)
    }

    @Test func outOfWindowItemsAreExcluded() {
        let meeting = Minutes(meetingAt: at(20))          // later in the month
        let note = Note(content: "later", title: "Later"); note.updatedAt = at(20)
        let convo = EmailConversation(threadKey: "k"); convo.accept()
        convo.messages = [message(at(20), .inbox)]
        let content = build(meetings: [meeting], notes: [note], conversations: [convo])
        #expect(content.meetings.isEmpty)
        #expect(content.notes.isEmpty)
        #expect(content.conversations.isEmpty)
    }

    // The bundle must window exactly like the report: weekend work folds back into Friday, so Saturday
    // items belong to a week ending Friday 9 Jan.
    @Test func weekendWorkFoldsIntoTheWeekLikeTheReport() {
        let meeting = Minutes(meetingAt: at(10, 11))      // Saturday
        let note = Note(content: "weekend", title: "W"); note.updatedAt = at(10, 12)
        let content = build(meetings: [meeting], notes: [note])
        #expect(content.meetings.count == 1)              // folded back to Friday 9 Jan, inside the week
        #expect(content.notes.count == 1)
    }

    @Test func aConversationWithNoMessagesInWindowIsDropped() {
        let convo = EmailConversation(threadKey: "k"); convo.accept()
        convo.messages = [message(at(2), .inbox), message(at(20), .sent)]   // either side of the week
        #expect(build(conversations: [convo]).conversations.isEmpty)
    }

    @Test func emptyStoreGivesAnEmptyBundleWithTheNotice() {
        let content = build()
        #expect(content.meetings.isEmpty && content.notes.isEmpty && content.conversations.isEmpty)
        #expect(!content.notice.isEmpty)
    }
}
