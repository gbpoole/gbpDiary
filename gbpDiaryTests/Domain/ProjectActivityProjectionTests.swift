import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct ProjectActivityProjectionTests {
    private let cal = Calendar(identifier: .gregorian)
    // 2024-01: 03 Wed · 05 Fri · 06 Sat · 08 Mon · 10 Wed.
    private func at(_ day: Int, _ hour: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2024, month: 1, day: day, hour: hour))!
    }
    private func report(interval: Range<Date>? = nil, tasks: [Task] = [], emails: [EmailMessage] = [],
                        meetings: [Minutes] = [], focusBlocks: [FocusBlock] = []) -> ProjectActivityReport {
        ProjectActivityProjection.report(interval: interval, tasks: tasks, emails: emails, meetings: meetings,
                                         focusBlocks: focusBlocks, calendar: cal)
    }
    private func email(_ subject: String, _ day: Int, importance: EmailImportance = .low,
                       projects: [Project] = []) -> EmailMessage {
        let e = EmailMessage(messageId: subject, account: "a", mailbox: "INBOX", direction: .inbox,
                             fromAddress: "x@y.com", fromName: nil, subject: subject, date: at(day))
        e.importance = importance
        e.projects = projects
        return e
    }

    @Test func meetingsTasksCommentsEmails_landUnderTheRightProjectWithLabels() {
        let nodes = Project(name: "NODES")
        let m = Minutes(meetingAt: at(3, 9)); m.projects = [nodes]; m.summary = "sprint"
        m.duration = Duration(value: 1, unit: .h)
        let done = Task(summary: "EoI draft"); done.project = nodes
        done.markCompleted(); done.completedAt = at(3, 14)
        let logged = Task(summary: "analysis"); logged.project = nodes
        logged.timeEntries = [TaskTimeEntry(date: at(3, 15), duration: Duration(value: 2, unit: .h),
                                            comment: "reduced the cube")]
        let mail = email("grant reply", 3, importance: .high, projects: [nodes])

        let r = report(tasks: [done, logged], emails: [mail], meetings: [m])
        let s = r.section(matching: "NODES")
        #expect(s != nil)
        let labels = s!.items.map(\.label)
        #expect(labels.contains("Meeting: sprint (1h)"))
        #expect(labels.contains("Completed: EoI draft"))
        #expect(labels.contains("reduced the cube (2h)"))
        #expect(labels.contains("Email: grant reply [H]"))
        // Every narrative item carries a click-through source and the project tag.
        #expect(s!.items.allSatisfy { $0.projectNames == ["NODES"] })
    }

    @Test func hoursAndWeeks_comeFromTheLedger() {
        let p = Project(name: "Alpha")
        let block = FocusBlock(duration: Duration(value: 3, unit: .h), slot: .allDay)
        block.project = p; block.dayRecord = DayRecord(date: at(3))
        let r = report(focusBlocks: [block])
        let s = r.section(matching: "Alpha")
        #expect(s?.hours == 3)
        #expect(s?.distinctWeeks == 1)
    }

    @Test func weekendItem_foldsToFriday() {
        let p = Project(name: "Gamma")
        let m = Minutes(meetingAt: at(6, 10)); m.projects = [p]; m.summary = "sat sync"   // Saturday
        let r = report(meetings: [m])
        let item = r.section(matching: "Gamma")?.items.first
        #expect(item != nil)
        #expect(cal.component(.weekday, from: item!.date) == 6)   // Friday
    }

    @Test func intervalFilter_dropsOutOfWindowItems() {
        let p = Project(name: "Beta")
        let inWindow = Task(summary: "in"); inWindow.project = p
        inWindow.markCompleted(); inWindow.completedAt = at(3)
        let outWindow = Task(summary: "out"); outWindow.project = p
        outWindow.markCompleted(); outWindow.completedAt = at(10)
        let r = report(interval: at(1)..<at(5), tasks: [inWindow, outWindow])
        let labels = r.section(matching: "Beta")?.items.map(\.label) ?? []
        #expect(labels.contains("Completed: in"))
        #expect(!labels.contains("Completed: out"))
    }

    @Test func projectWithItemsButNoLoggedHours_stillAppears() {
        let p = Project(name: "Zeta")
        let mail = email("fyi", 3, projects: [p])
        let r = report(emails: [mail])
        let s = r.section(matching: "Zeta")
        #expect(s != nil)
        #expect(s?.hours == 0)
        #expect(s?.items.map(\.label) == ["Email: fyi"])
    }

    @Test func emptyCommentEntries_areSkipped() {
        let p = Project(name: "Eta")
        let t = Task(summary: "t"); t.project = p
        t.timeEntries = [
            TaskTimeEntry(date: at(3), duration: Duration(value: 1, unit: .h), comment: "   "),
            TaskTimeEntry(date: at(3), duration: Duration(value: 1, unit: .h), comment: nil),
        ]
        let r = report(tasks: [t])
        // Time still logged (hours come from the ledger), but no blank comment bullets.
        let s = r.section(matching: "Eta")
        #expect(s?.hours == 2)
        #expect(s?.items.contains { $0.kind == .loggedComment } == false)
    }

    @Test func emails_areImportanceFirstAndCapped() {
        let p = Project(name: "Theta")
        var mails: [EmailMessage] = []
        for i in 1...8 { mails.append(email("low\(i)", 3, importance: .low, projects: [p])) }
        mails.append(email("hi", 4, importance: .high, projects: [p]))
        let r = ProjectActivityProjection.report(interval: nil, tasks: [], emails: mails, meetings: [],
                                                 focusBlocks: [], calendar: cal, maxEmailsPerProject: 3)
        let emailItems = r.section(matching: "Theta")?.items.filter { $0.kind == .email } ?? []
        #expect(emailItems.count == 3)
        #expect(emailItems.contains { $0.label == "Email: hi [H]" })   // high survives the cap
    }

    @Test func noProjectHoursBucket_isNotASection() {
        let block = FocusBlock(duration: Duration(value: 2, unit: .h), slot: .allDay)
        block.dayRecord = DayRecord(date: at(3))   // no project/task → "(no project)" in the ledger
        let r = report(focusBlocks: [block])
        #expect(r.section(matching: TimeLedger.noProject) == nil)
    }
}
