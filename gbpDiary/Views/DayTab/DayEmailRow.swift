import SwiftUI
import SwiftData

// Compact one-line-forward email row for the diary Email section. The persistent `EmailConversation` owns
// the cross-cutting state (person / project(s) / importance / triage / time), set once for the whole
// conversation; the row renders that day's message slice (passed in, respecting the weekend windows).
// The person chip resolves the sender (ResolveAttendeeSheet); the project picker files the conversation;
// time logs against the conversation. No "Sent" chip — the icon shows direction.
struct DayEmailThreadRow: View {
    let conversation: EmailConversation
    // This day's messages in the conversation (latest-first), already scoped to the weekend windows.
    let dayMessages: [EmailMessage]
    // This day's logged conversation time (hours).
    let dayLoggedHours: Double
    let onReconcile: () -> Void

    @State private var mailService = MailScriptService()
    @State private var openError: String?
    @State private var openingTask: Task?
    @State private var expanded = false
    @State private var showingLogTime = false

    private var latestDayMessage: EmailMessage? { dayMessages.first }
    private var dayCount: Int { dayMessages.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            mainRow
            // Drill-down: each message in this day's slice — sent messages keep their time-logging row.
            if expanded && dayCount > 1 {
                ForEach(dayMessages, id: \.persistentModelID) { message in
                    if message.direction == .sent {
                        SentEmailActivityRow(email: message)
                    } else {
                        messageRow(message)
                    }
                }
            }
        }
        .contextMenu {
            if let latest = latestDayMessage {
                Button("Open in Mail", systemImage: "envelope.open") { openInMail(latest) }
                EmailExperimentInChatButton(email: latest)
            }
            Button("Log time…", systemImage: "clock") { showingLogTime = true }
            Button("Regenerate summary", systemImage: "sparkles") { regenerateSummary() }
            Menu("Set importance") {
                Button("High") { setImportance(.high) }
                Button("Medium") { setImportance(.medium) }
                Button("Low") { setImportance(.low) }
            }
        }
        .alert("Couldn't open email", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(openError ?? "") }
        .sheet(item: $openingTask) { task in
            TaskEditorSheet(task: task, defaultDate: task.originEmail?.date ?? Date())
        }
        .sheet(isPresented: $showingLogTime) {
            LogTimeSheet(presetDate: latestDayMessage?.date ?? Date(), presetConversation: conversation)
        }
    }

    // The conversation's headline row: person/project/importance chips + the day's summary line.
    // A single envelope icon for every conversation — the sent/received breakdown gives direction context.
    private var countText: String {
        let sent = dayMessages.filter { $0.direction == .sent }.count
        let recv = dayMessages.filter { $0.direction == .inbox }.count
        var parts: [String] = []
        if sent > 0 { parts.append("\(sent) sent") }
        if recv > 0 { parts.append("\(recv) recv") }
        return parts.joined(separator: " · ")
    }

    // Expand chevron for multi-message days; a neutral bullet (same width) for single-message ones so
    // the content to the right stays aligned across all rows.
    @ViewBuilder private var expandControl: some View {
        Group {
            if dayCount > 1 {
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(expanded ? "Hide messages" : "Show each message")
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 4))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 12, alignment: .center)
    }

    private var mainRow: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    // Leading control: expand chevron for multi-message days, else a neutral bullet — a
                    // fixed-width slot so everything to its right aligns across rows.
                    expandControl
                    personChip
                    ForEach(conversation.projects, id: \.persistentModelID) { project in
                        Chip(label: project.name, color: AppTheme.project)
                    }
                    // Envelope icon + direction/volume breakdown, after the project chip.
                    Image(systemName: "envelope")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(countText)
                        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        .fixedSize()
                    if conversation.taskCount > 0 {
                        EmailTodoChip(count: conversation.taskCount, hasOpen: conversation.hasOpenTasks,
                                      onOpen: { openingTask = conversation.tasks.first })
                    }
                    EmailImportanceChip(importance: conversation.importance)
                    Spacer(minLength: 0)
                    if dayLoggedHours > 0 {
                        Chip(label: TimeFormat.short(hours: dayLoggedHours), color: AppTheme.duration)
                    }
                    if let latest = latestDayMessage {
                        Text(latest.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                EmailContentLine(subject: latestDayMessage?.subject ?? conversation.subject,
                                 summary: latestDayMessage?.summary,
                                 isSummarizing: latestDayMessage?.isSummarizing ?? false)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { if let latest = latestDayMessage { openInMail(latest) } }
    }

    // A single message inside an expanded day: direction + time + that message's own summary.
    private func messageRow(_ message: EmailMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: message.direction == .sent ? "paperplane" : "envelope")
                .foregroundStyle(.tertiary).font(.system(size: 11)).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(message.direction == .sent ? "Sent" : "Received")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(message.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                EmailContentLine(subject: message.subject, summary: message.summary,
                                 isSummarizing: message.isSummarizing, font: .caption)
            }
        }
        .padding(.leading, 40).padding(.trailing).padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture { openInMail(message) }
    }

    private func regenerateSummary() {
        for message in dayMessages {
            message.summary = nil
            message.summaryState = EmailSummaryState.pending.rawValue
        }
    }

    // Importance is a single write on the conversation (it owns the cross-cutting state).
    private func setImportance(_ importance: EmailImportance) {
        conversation.importance = importance
    }

    private func openInMail(_ message: EmailMessage) {
        mailService.openMessage(message) { result in
            if case .failure(let error) = result { openError = error.userMessage }
        }
    }

    @ViewBuilder private var personChip: some View {
        Button(action: onReconcile) {
            if let person = conversation.person {
                Chip(label: person.name, color: AppTheme.person)
            } else {
                let label = conversation.fromName?.isEmpty == false ? conversation.fromName!
                    : (conversation.fromAddress.isEmpty ? "Unrecognized" : conversation.fromAddress)
                Chip(label: label, color: AppTheme.warning)
            }
        }
        .buttonStyle(.plain)
        .help(conversation.person == nil
              ? "Unrecognized — click to link an existing person or create a new one"
              : "Linked person — click to change")
    }
}

// A chip showing an email's linked-to-do status ("to-do" / "N to-dos" while open, "done" when all
// complete). Shared by the diary email row and the triage window. Tappable when `onOpen` is provided.
struct EmailTodoChip: View {
    let count: Int
    let hasOpen: Bool
    var onOpen: (() -> Void)? = nil

    private var label: String { hasOpen ? (count == 1 ? "to-do" : "\(count) to-dos") : "done" }
    private var color: Color { hasOpen ? AppTheme.action : AppTheme.completed }

    var body: some View {
        Group {
            if let onOpen {
                Button(action: onOpen) { Chip(label: label, color: color) }.buttonStyle(.plain)
            } else {
                Chip(label: label, color: color)
            }
        }
        .help(hasOpen ? "Open the linked to-do" : "To-do completed — click to open")
    }
}

// The email's content line: shows the on-device AI **summary** when ready (primary text), otherwise
// falls back to the **subject** (de-emphasised, with a "summarising…" hint while one is generated).
struct EmailContentLine: View {
    let subject: String
    let summary: String?
    var isSummarizing: Bool = false
    var font: Font = .callout
    var lineLimit: Int = 2

    var body: some View {
        if let summary, !summary.isEmpty {
            Text(summary)
                .font(font)
                .lineLimit(lineLimit)
                .help("AI summary")
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(subject.isEmpty ? "(no subject)" : subject)
                    .font(font)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if isSummarizing {
                    Text("summarising…")
                        .font(.caption2)
                        .italic()
                        .foregroundStyle(.tertiary)
                }
            }
            .help(isSummarizing ? "Subject — summary is being generated" : "Subject")
        }
    }
}
