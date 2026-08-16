import Foundation
@testable import gbpDiary

// A fixed, deterministic corpus + retrieval for the Chat evaluation harness. Retrieval is lexical-only
// (no NLEmbedding) so results are reproducible in CI; the seeded text contains the query terms the
// golden questions use, and scope filtering (kind/project/interval) enforces the must-include/exclude
// expectations. `now` is frozen so date-window parsing is stable.
@MainActor
enum ChatEvalCorpus {
    static let calendar = Calendar(identifier: .gregorian)
    // Wednesday, 17 June 2026, 12:00 — a plain weekday so week/month math is unambiguous.
    static let now = Calendar(identifier: .gregorian).date(from: DateComponents(
        year: 2026, month: 6, day: 17, hour: 12))!

    static let nodes = "NODES - 2026B"
    static let other = "Other Project"
    static let knownProjectNames = [nodes, other]

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    struct Fixture {
        let documents: [ChatRetrievalDocument]
        let chunks: [ChatRetrievalChunk]
        let ids: [String: UUID]
        let timeRecords: [ChatTimeRecord]
        let activityItems: [ChatActivityItem]

        func retrieve(_ query: String, _ limit: Int) -> (chunks: [ChatRankedChunk], error: String?) {
            (ChatHybridRanker().rank(query: query, chunks: chunks, embedder: nil, limit: limit), nil)
        }
        func key(_ name: String, _ kind: ChatSourceKind) -> ChatSourceKey {
            ChatSourceKey(kind: kind, modelID: ids[name]!)
        }
        func activity(_ interval: Range<Date>) -> ChatActivityDigest {
            ChatActivityDigestBuilder.build(items: activityItems, interval: interval)
        }
        func document(_ name: String, _ kind: ChatSourceKind) -> ChatRetrievalDocument? {
            documents.first { $0.source.key == key(name, kind) }
        }
    }

    static func build() -> Fixture {
        let nodesProject = Project(name: nodes, id: uuid(1))
        let otherProject = Project(name: other, id: uuid(2))

        // Emails across the project and the date windows (subjects carry "NODES"/"Other" for lexical hits).
        let nodesEmailThisWeek = email(uuid(10), subject: "NODES status this week",
                                       summary: "NODES progress update.", date: date(2026, 6, 16),
                                       projects: [nodesProject], importance: .high)
        let nodesEmailLastWeek = email(uuid(11), subject: "NODES review",
                                       summary: "NODES review notes.", date: date(2026, 6, 10),
                                       projects: [nodesProject])
        let otherEmailLastWeek = email(uuid(12), subject: "Other Project sync",
                                       summary: "Other Project sync notes.", date: date(2026, 6, 10),
                                       projects: [otherProject])
        let nodesEmailFebruary = email(uuid(13), subject: "NODES kickoff",
                                       summary: "NODES kickoff.", date: date(2026, 2, 10),
                                       projects: [nodesProject])

        // Meetings: one far out of window (February), one in "last month" (May) with a duration, and one
        // on a SATURDAY in last week (13 Jun 2026) — it must fold to Friday and never read as "Saturday".
        let febMeeting = meeting(uuid(20), summary: "NODES February planning",
                                 date: date(2026, 2, 10), projects: [nodesProject])
        let mayMeeting = meeting(uuid(21), summary: "NODES May planning",
                                 date: date(2026, 5, 20), projects: [nodesProject],
                                 duration: Duration(value: 1, unit: .h))
        let satMeeting = meeting(uuid(22), summary: "NODES sprint push",
                                 date: date(2026, 6, 13), projects: [nodesProject],
                                 duration: Duration(value: 1, unit: .h))

        let meetings = [febMeeting, mayMeeting, satMeeting]
        let result = ChatCorpusBuilder().build(
            projects: [nodesProject, otherProject], tasks: [], people: [], institutions: [],
            meetings: meetings, notes: [], days: [], documents: [],
            emails: [nodesEmailThisWeek, nodesEmailLastWeek, otherEmailLastWeek, nodesEmailFebruary],
            attachments: [])
        let activityItems = meetings.map { m -> ChatActivityItem in
            let ref = ChatSourceReference(id: m.id, kind: .meeting, title: m.summary ?? "Meeting", detail: nil,
                                          navigationKind: .meeting, navigationID: m.id)
            return ChatActivityItem(date: ChatWeekendFold.fold(m.meetingAt, kind: .meeting, calendar: calendar),
                                    label: "Meeting: \(m.summary ?? "Meeting")", source: ref)
        }

        let documents = result.documents
        let chunks = documents.flatMap { ChatChunker.chunks(document: $0) }

        // Deterministic time data: 1h logged against NODES in May (last month), plus 2h in February (outside).
        let timeRecords = [
            ChatTimeRecord(sourceKey: "may-meeting", date: date(2026, 5, 20), hours: 1.0, projectNames: [nodes]),
            ChatTimeRecord(sourceKey: "feb-meeting", date: date(2026, 2, 10), hours: 2.0, projectNames: [nodes]),
        ]

        let ids: [String: UUID] = [
            "nodesProject": uuid(1), "otherProject": uuid(2),
            "nodesEmailThisWeek": uuid(10), "nodesEmailLastWeek": uuid(11),
            "otherEmailLastWeek": uuid(12), "nodesEmailFebruary": uuid(13),
            "febMeeting": uuid(20), "mayMeeting": uuid(21), "satMeeting": uuid(22),
        ]
        return Fixture(documents: documents, chunks: chunks, ids: ids, timeRecords: timeRecords,
                       activityItems: activityItems)
    }

    private static func email(_ id: UUID, subject: String, summary: String, date: Date,
                              projects: [Project], importance: EmailImportance = .low) -> EmailMessage {
        let e = EmailMessage(messageId: id.uuidString, account: "local", mailbox: "INBOX",
                             direction: .inbox, fromAddress: "a@b.com", fromName: nil,
                             subject: subject, date: date, id: id)
        e.summary = summary
        e.projects = projects
        e.importance = importance
        return e
    }

    private static func meeting(_ id: UUID, summary: String, date: Date, projects: [Project],
                                duration: Duration? = nil) -> Minutes {
        let m = Minutes(meetingAt: date, id: id)
        m.summary = summary
        m.projects = projects
        m.duration = duration
        return m
    }
}
