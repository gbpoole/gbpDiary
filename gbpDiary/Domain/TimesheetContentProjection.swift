import Foundation

// Gathers the TEXT behind a reporting period for a full export: complete meeting minutes, note markdown,
// and email correspondence — so an agent can work from the actual content rather than from row labels.
//
// Windowing matches the report exactly (`TimesheetProjection`): meetings and notes are work, so a weekend
// one folds back to Friday; a sent email is work (→ Friday) while received mail is inbound (→ Monday). If
// this drifted from the report, the bundle would describe a different period than the figures beside it.
//
// There is no email body here and there cannot be: the app reads a body transiently from Mail, summarises
// it on device and discards it. Only the subject and that summary are ever stored.
@MainActor
enum TimesheetContentProjection {
    static func build(interval: Range<Date>,
                      meetings: [Minutes],
                      notes: [Note],
                      conversations: [EmailConversation],
                      calendar: Calendar = .current) -> TimesheetExportSnapshot.FullContent {
        func inWindow(_ date: Date) -> Bool { interval.contains(date) }
        func work(_ date: Date) -> Date { ChatWeekendFold.foldWork(date, calendar: calendar) }

        let meetingContent = meetings
            .filter { inWindow(work($0.meetingAt)) }
            .sorted { $0.meetingAt < $1.meetingAt }
            .map { meeting in
                TimesheetExportSnapshot.MeetingContent(
                    id: meeting.id,
                    summary: meeting.summary ?? "",
                    meetingAt: meeting.meetingAt,
                    durationHours: meeting.duration?.hoursNormalized ?? 0,
                    projects: meeting.projects.map(\.name).sorted(),
                    attendees: meeting.attendees.map(\.name).sorted(),
                    // Complete, not the report's clipped extract. `minutesContent` is the legacy
                    // pre-note field, still worth carrying for meetings never opened since.
                    minutesMarkdown: meeting.note?.content ?? meeting.minutesContent ?? "")
            }

        // A meeting's minutes are carried on the meeting itself, so they are not repeated here.
        let noteContent = notes
            .filter { $0.minutes == nil && inWindow(work($0.updatedAt)) && !$0.content.isEmpty }
            .sorted { $0.updatedAt < $1.updatedAt }
            .map { note in
                TimesheetExportSnapshot.NoteContent(
                    id: note.id,
                    title: note.title,
                    project: note.project?.name ?? "",
                    day: note.dayRecord?.date,
                    updatedAt: note.updatedAt,
                    markdown: note.content)
            }

        // Dismissed conversations are spam by the user's own classification — excluded, as elsewhere.
        let conversationContent = conversations
            .filter { $0.triageState != .dismissed }
            .compactMap { convo -> TimesheetExportSnapshot.ConversationContent? in
                let messages = convo.messages
                    .filter { inWindow(folded($0, calendar: calendar)) }
                    .sorted { $0.date < $1.date }
                guard !messages.isEmpty else { return nil }
                return TimesheetExportSnapshot.ConversationContent(
                    id: convo.id,
                    subject: convo.displaySubject,
                    projects: convo.projects.map(\.name).sorted(),
                    otherParty: convo.person?.name ?? "",
                    importance: convo.importance.rawValue,
                    loggedHours: convo.timeEntries
                        .filter { inWindow(work($0.date)) }
                        .reduce(0) { $0 + $1.duration.hoursNormalized },
                    messages: messages.map { message in
                        TimesheetExportSnapshot.MessageContent(
                            id: message.id,
                            subject: message.subject,
                            direction: message.direction.rawValue,
                            date: message.date,
                            from: message.fromName ?? message.fromAddress,
                            summary: message.summary ?? "")
                    })
            }
            .sorted { ($0.messages.last?.date ?? .distantPast) < ($1.messages.last?.date ?? .distantPast) }

        return .init(notice: TimesheetDataExport.contentNotice,
                     meetings: meetingContent,
                     notes: noteContent,
                     conversations: conversationContent)
    }

    /// A message's reporting date: sent mail is work (weekend → Friday), received is inbound
    /// (weekend → Monday) — the same split `TimesheetProjection` uses.
    private static func folded(_ message: EmailMessage, calendar: Calendar) -> Date {
        message.direction == .sent
            ? ChatWeekendFold.foldWork(message.date, calendar: calendar)
            : ChatWeekendFold.fold(message.date, kind: .email, calendar: calendar)
    }
}
