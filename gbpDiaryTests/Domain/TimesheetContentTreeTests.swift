import Foundation
import Testing
@testable import gbpDiary

// The exported markdown tree. Pure — the whole layout is asserted without touching the filesystem, which is
// why `compose` returns path→contents rather than writing.
struct TimesheetContentTreeTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return c
    }()
    private func at(_ day: Int, _ hour: Int = 10) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
    }

    private func meeting(_ summary: String, _ day: Int, projects: [String] = ["NODES"],
                         minutes: String = "# Agreed\n- manifest v2") -> TimesheetExportSnapshot.MeetingContent {
        .init(id: UUID(), summary: summary, meetingAt: at(day), durationHours: 1,
              projects: projects, attendees: ["Asher"], minutesMarkdown: minutes)
    }
    private func note(_ title: String, _ day: Int, project: String = "NODES",
                      markdown: String = "The parser rewrite.") -> TimesheetExportSnapshot.NoteContent {
        .init(id: UUID(), title: title, project: project, day: nil, updatedAt: at(day), markdown: markdown)
    }
    private func message(_ id: UUID = UUID(), _ day: Int = 6, direction: String = "inbox",
                         summary: String = "They asked about the quota") -> TimesheetExportSnapshot.MessageContent {
        .init(id: id, subject: "Re: grant", direction: direction, date: at(day), from: "Asher", summary: summary)
    }
    private func conversation(_ subject: String, projects: [String] = ["NODES"],
                              messages: [TimesheetExportSnapshot.MessageContent]) -> TimesheetExportSnapshot.ConversationContent {
        .init(id: UUID(), subject: subject, projects: projects, otherParty: "Asher",
              importance: "high", loggedHours: 0.5, messages: messages)
    }
    private func content(meetings: [TimesheetExportSnapshot.MeetingContent] = [],
                         notes: [TimesheetExportSnapshot.NoteContent] = [],
                         conversations: [TimesheetExportSnapshot.ConversationContent] = [])
    -> TimesheetExportSnapshot.FullContent {
        .init(notice: TimesheetDataExport.contentNotice, meetings: meetings, notes: notes,
              conversations: conversations)
    }
    private func compose(_ c: TimesheetExportSnapshot.FullContent,
                         bodies: [UUID: TimesheetEmailBody] = [:],
                         trimQuotedHistory: Bool = true) -> [TimesheetExportFile] {
        TimesheetContentTree.compose(content: c, periodLabel: "5 Jan 2026 – 9 Jan 2026", bodies: bodies,
                                     generatedAt: at(9), trimQuotedHistory: trimQuotedHistory, calendar: cal)
    }
    private func paths(_ files: [TimesheetExportFile]) -> [String] { files.map(\.path).sorted() }
    private func file(_ files: [TimesheetExportFile], _ path: String) -> String? {
        files.first { $0.path == path }?.contents
    }

    // MARK: layout

    @Test func oneDirectoryPerProjectWithKindSubdirectories() {
        let files = compose(content(meetings: [meeting("Requirements gathering", 6)],
                                    notes: [note("Parser design", 7)],
                                    conversations: [conversation("Re: grant", messages: [message()])]))
        #expect(paths(files) == ["NODES/email/2026-01-06 Re grant.md",
                                 "NODES/meetings/2026-01-06 Requirements gathering.md",
                                 "NODES/notes/2026-01-07 Parser design.md",
                                 "README.md"])
    }

    // An agent reading one project's folder should see everything that touched it, with no link to follow.
    @Test func multiProjectItemIsWrittenUnderEachProject() {
        let files = compose(content(meetings: [meeting("Joint review", 6, projects: ["NODES", "2027A"])]))
        #expect(paths(files).contains("NODES/meetings/2026-01-06 Joint review.md"))
        #expect(paths(files).contains("2027A/meetings/2026-01-06 Joint review.md"))
        // Both copies are generated together from one source, and each names every project.
        let a = file(files, "NODES/meetings/2026-01-06 Joint review.md")
        #expect(a == file(files, "2027A/meetings/2026-01-06 Joint review.md"))
        #expect(a?.contains("**Projects:** NODES, 2027A") == true)
    }

    @Test func contentWithNoProjectLandsUnderUnattributed() {
        let files = compose(content(meetings: [meeting("Standup", 6, projects: [])],
                                    notes: [note("Loose", 7, project: "")],
                                    conversations: [conversation("Building access", projects: [],
                                                                 messages: [message()])]))
        #expect(paths(files).contains("Unattributed/meetings/2026-01-06 Standup.md"))
        #expect(paths(files).contains("Unattributed/notes/2026-01-07 Loose.md"))
        #expect(paths(files).contains("Unattributed/email/2026-01-06 Building access.md"))
    }

    // The sanitiser keeps only alphanumerics + space/-/_, so a hostile project name cannot escape the root.
    @Test func projectNamesAreSanitisedAndCannotEscapeTheRoot() {
        #expect(TimesheetContentTree.directoryName(project: "../../etc") == "etc")
        #expect(TimesheetContentTree.directoryName(project: "NODES/2026") == "NODES2026")
        #expect(TimesheetContentTree.directoryName(project: "") == TimesheetContentTree.unattributedDirectory)
        let files = compose(content(meetings: [meeting("x", 6, projects: ["../../etc"])]))
        #expect(paths(files).contains("etc/meetings/2026-01-06 x.md"))
    }

    @Test func everyPathIsRelativeWithNoDotDot() {
        let files = compose(content(meetings: [meeting("x", 6, projects: ["../../etc"])],
                                    notes: [note("../y", 7)],
                                    conversations: [conversation("../z", messages: [message()])]))
        for path in files.map(\.path) {
            #expect(!path.hasPrefix("/"))
            #expect(!path.split(separator: "/").contains(".."))
        }
    }

    @Test func duplicateTitlesGetDistinctDeterministicNames() {
        let files = compose(content(meetings: [meeting("Standup", 6), meeting("Standup", 6),
                                               meeting("Standup", 6)]))
        #expect(paths(files).contains("NODES/meetings/2026-01-06 Standup.md"))
        #expect(paths(files).contains("NODES/meetings/2026-01-06 Standup 2.md"))
        #expect(paths(files).contains("NODES/meetings/2026-01-06 Standup 3.md"))
    }

    @Test func untitledItemsFallBackToTheirKind() {
        let files = compose(content(meetings: [meeting("", 6)], notes: [note("", 7)]))
        #expect(paths(files).contains("NODES/meetings/2026-01-06 Meeting.md"))
        #expect(paths(files).contains("NODES/notes/2026-01-07 Note.md"))
    }

    // MARK: file contents

    @Test func meetingFileCarriesCompleteMinutesAndMetadata() {
        let long = String(repeating: "Discussed the manifest. ", count: 80)
        let files = compose(content(meetings: [meeting("Requirements", 6, minutes: long)]))
        let text = file(files, "NODES/meetings/2026-01-06 Requirements.md") ?? ""
        #expect(text.hasPrefix("# Requirements"))
        #expect(text.contains("**Attendees:** Asher"))
        #expect(text.contains(long))        // complete, not clipped
    }

    @Test func noteFileCarriesFullMarkdown() {
        let files = compose(content(notes: [note("Design", 7, markdown: "# Design\n\nBody.")]))
        let text = file(files, "NODES/notes/2026-01-07 Design.md") ?? ""
        #expect(text.contains("**Project:** NODES"))
        #expect(text.contains("# Design\n\nBody."))
    }

    @Test func conversationListsMessagesOldestFirstWithSummaries() {
        let first = message(UUID(), 6, summary: "They asked about the quota")
        let second = message(UUID(), 7, direction: "sent", summary: "You confirmed it")
        let files = compose(content(conversations: [conversation("Re: grant", messages: [first, second])]))
        let text = file(files, "NODES/email/2026-01-07 Re grant.md") ?? ""
        #expect(text.contains("**Importance:** high"))
        #expect(text.contains("_Summary:_ They asked about the quota"))
        let a = text.range(of: "They asked about the quota")!.lowerBound
        let b = text.range(of: "You confirmed it")!.lowerBound
        #expect(a < b)
    }

    // MARK: bodies

    @Test func aFetchedBodyIsEmbedded() {
        let id = UUID()
        let files = compose(content(conversations: [conversation("Re: grant", messages: [message(id)])]),
                            bodies: [id: .fetched("Hi Greg,\n\nThe quota is fine.")])
        let text = file(files, "NODES/email/2026-01-06 Re grant.md") ?? ""
        #expect(text.contains("**Body**"))
        #expect(text.contains("The quota is fine."))
    }

    // Partial failure is normal (archived/moved mail), so an absent body always states its reason.
    @Test func everyAbsentBodyStatesWhy() {
        func render(_ outcome: TimesheetEmailBody) -> String {
            let id = UUID()
            let files = compose(content(conversations: [conversation("Re: grant", messages: [message(id)])]),
                                bodies: [id: outcome])
            return file(files, "NODES/email/2026-01-06 Re grant.md") ?? ""
        }
        #expect(render(.failed("Mail returned an error: [-1728]")).contains("_Body unavailable: Mail returned an error: [-1728]_"))
        #expect(render(.skippedNotRelevant).contains("not filed to a project"))
        #expect(render(.skippedNoMessageID).contains("no Mail id stored"))
        #expect(render(.skippedStopped).contains("the export was stopped"))
        #expect(render(.notRequested).contains("_Body not requested._"))
    }

    @Test func noBodyAppearsAnywhereWhenNoneWereFetched() {
        let files = compose(content(conversations: [conversation("Re: grant", messages: [message()])]))
        let text = file(files, "NODES/email/2026-01-06 Re grant.md") ?? ""
        #expect(!text.contains("**Body**"))
        #expect(text.contains("_Body not requested._"))
    }

    // A body containing a code fence must not break out of its own block.
    @Test func fenceSurvivesBackticksInTheBody() {
        let body = "Here is code:\n```swift\nlet x = 1\n```\nthanks"
        let fenced = TimesheetContentTree.fencedBlock(body)
        #expect(fenced.hasPrefix("````text"))
        #expect(fenced.hasSuffix("````"))
        #expect(fenced.contains(body))
    }

    @Test func oversizeBodiesAreTruncatedWithANotice() {
        let huge = String(repeating: "x", count: TimesheetContentTree.maxBodyCharacters + 500)
        guard case .truncated(let kept, let original) = TimesheetContentTree.clamp(huge) else {
            Issue.record("expected truncation"); return
        }
        #expect(kept.count == TimesheetContentTree.maxBodyCharacters)
        #expect(original == huge.count)

        let id = UUID()
        let files = compose(content(conversations: [conversation("Re: grant", messages: [message(id)])]),
                            bodies: [id: .truncated(kept, originalCount: original)])
        #expect(file(files, "NODES/email/2026-01-06 Re grant.md")?.contains("_Truncated to") == true)
        #expect(TimesheetContentTree.clamp("short") == .fetched("short"))
    }

    // A raw reply repeats the whole chain; each earlier message is already its own file, so trimming
    // removes duplication rather than information — and the file says it did.
    @Test func quotedHistoryIsTrimmedAndSaidSo() {
        let id = UUID()
        let body = "The quota is fine.\n\nOn 5 Jan 2026, Asher wrote:\n> what about the quota?"
        let trimmed = compose(content(conversations: [conversation("Re: grant", messages: [message(id)])]),
                              bodies: [id: .fetched(body)])
        let text = file(trimmed, "NODES/email/2026-01-06 Re grant.md") ?? ""
        #expect(text.contains("The quota is fine."))
        #expect(!text.contains("what about the quota?"))
        #expect(text.contains("_Quoted reply history trimmed"))

        let raw = compose(content(conversations: [conversation("Re: grant", messages: [message(id)])]),
                          bodies: [id: .fetched(body)], trimQuotedHistory: false)
        #expect(file(raw, "NODES/email/2026-01-06 Re grant.md")?.contains("what about the quota?") == true)
    }

    // MARK: index

    @Test func indexListsEveryFileAndTheBodyRollUp() {
        let id = UUID(), failed = UUID()
        let files = compose(content(meetings: [meeting("Requirements", 6)],
                                    conversations: [conversation("Re: grant",
                                                                 messages: [message(id), message(failed, 7)])]),
                            bodies: [id: .fetched("hello"), failed: .failed("gone")])
        let index = file(files, "README.md") ?? ""
        #expect(index.contains("# Content — 5 Jan 2026 – 9 Jan 2026"))
        #expect(index.contains("**Email bodies:** 1 fetched, 1 unavailable, 0 not fetched."))
        #expect(index.contains("## NODES"))
        #expect(index.contains("2026-01-06%20Requirements.md"))
        #expect(index.contains(TimesheetContentTree.bodyWarning))   // the directory is sensitive
    }

    @Test func indexSaysWhenNoBodiesWereRequested() {
        let index = file(compose(content(conversations: [conversation("Re: grant", messages: [message()])])),
                         "README.md") ?? ""
        #expect(index.contains("No email bodies were requested"))
        #expect(!index.contains(TimesheetContentTree.bodyWarning))
    }

    @Test func emptyPeriodIsJustAnIndexSayingSo() {
        let files = compose(content())
        #expect(files.map(\.path) == ["README.md"])
        #expect(file(files, "README.md")?.contains("No meetings, notes or correspondence") == true)
    }
}
