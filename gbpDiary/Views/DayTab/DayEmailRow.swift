import SwiftUI
import SwiftData

// A thread of the day's emails sharing a subject (ignoring Re:/Fwd:) and the same other party.
// Rendered as one compact row; person/project edits apply to every message in the thread.
struct EmailThread: Identifiable {
    let key: String
    let messages: [EmailMessage]   // sorted latest-first

    var id: String { key }
    var latest: EmailMessage { messages[0] }
    var subject: String { latest.subject.isEmpty ? "(no subject)" : latest.subject }
    var person: Person? { messages.first(where: { $0.person != nil })?.person }
    var fromName: String? { latest.fromName }
    var fromAddress: String { latest.fromAddress }
    var direction: EmailDirection { latest.direction }
    var count: Int { messages.count }
    var date: Date { latest.date }

    /// On-device AI summary (the latest message's) and whether it's still being generated.
    var summary: String? { latest.summary }
    var isSummarizing: Bool { latest.isSummarizing }

    /// To-dos made from any message in the thread.
    var tasks: [Task] { messages.flatMap(\.tasks) }
    var taskCount: Int { tasks.count }
    var hasOpenTasks: Bool { tasks.contains(where: \.isOpen) }

    /// Union of projects across the thread's messages (de-duplicated, order preserved).
    var projects: [Project] {
        var seen = Set<PersistentIdentifier>()
        var out: [Project] = []
        for m in messages {
            for p in m.projects where seen.insert(p.persistentModelID).inserted { out.append(p) }
        }
        return out
    }
}

// Compact one-line-forward email row: direction icon + person chip (in place of the name) + project
// chips + count/time on the first line, subject on the second. The person chip resolves the sender
// (ResolveAttendeeSheet); the project picker files the whole thread. No "Sent" chip — the icon shows it.
struct DayEmailThreadRow: View {
    let thread: EmailThread
    let onReconcile: () -> Void

    @State private var mailService = MailScriptService()
    @State private var openError: String?
    @State private var openingTask: Task?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: thread.direction == .sent ? "paperplane" : "envelope")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    personChip
                    ForEach(thread.projects, id: \.persistentModelID) { project in
                        Chip(label: project.name, color: AppTheme.project)
                    }
                    if thread.taskCount > 0 {
                        EmailTodoChip(count: thread.taskCount, hasOpen: thread.hasOpenTasks,
                                      onOpen: { openingTask = thread.tasks.first })
                    }
                    Spacer(minLength: 0)
                    if thread.count > 1 {
                        Chip(label: "\(thread.count)", color: .gray)
                    }
                    Text(thread.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                EmailContentLine(subject: thread.subject, summary: thread.summary,
                                 isSummarizing: thread.isSummarizing)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { openInMail() }   // tapping the email opens it in Mail (the default action)
        .contextMenu {
            Button("Open in Mail", systemImage: "envelope.open") { openInMail() }
            EmailExperimentInChatButton(email: thread.latest)
            Button("Regenerate summary", systemImage: "sparkles") { regenerateSummary() }
        }
        .alert("Couldn't open email", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(openError ?? "") }
        .sheet(item: $openingTask) { task in
            TaskEditorSheet(task: task, defaultDate: task.originEmail?.date ?? Date())
        }
    }

    private func regenerateSummary() {
        for message in thread.messages {
            message.summary = nil
            message.summaryState = EmailSummaryState.pending.rawValue
        }
    }

    private func openInMail() {
        mailService.openMessage(thread.latest) { result in
            if case .failure(let error) = result { openError = error.userMessage }
        }
    }

    @ViewBuilder private var personChip: some View {
        Button(action: onReconcile) {
            if let person = thread.person {
                Chip(label: person.name, color: AppTheme.person)
            } else {
                let label = thread.fromName?.isEmpty == false ? thread.fromName!
                    : (thread.fromAddress.isEmpty ? "Unrecognized" : thread.fromAddress)
                Chip(label: label, color: AppTheme.warning)
            }
        }
        .buttonStyle(.plain)
        .help(thread.person == nil
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
