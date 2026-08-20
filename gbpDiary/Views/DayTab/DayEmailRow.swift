import SwiftUI
import SwiftData

// Compact one-line-forward email row: direction icon + person chip (in place of the name) + project
// chips + count/time on the first line, subject on the second. The person chip resolves the sender
// (ResolveAttendeeSheet); the project picker files the whole thread. No "Sent" chip — the icon shows it.
struct DayEmailThreadRow: View {
    let thread: EmailThread
    let onReconcile: () -> Void

    @State private var mailService = MailScriptService()
    @State private var openError: String?
    @State private var openingTask: Task?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            mainRow
            // Drill-down: each message in the thread with its own per-email summary.
            if expanded && thread.count > 1 {
                ForEach(thread.messages, id: \.persistentModelID) { message in
                    messageRow(message)
                }
            }
        }
        .contextMenu {
            Button("Open in Mail", systemImage: "envelope.open") { openInMail(thread.latest) }
            EmailExperimentInChatButton(email: thread.latest)
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
    }

    // The thread's headline row: person/project/importance chips + the whole-thread summary line.
    private var mainRow: some View {
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
                    EmailImportanceChip(importance: thread.importance)
                    Spacer(minLength: 0)
                    // Multi-message threads expand to per-message summaries.
                    if thread.count > 1 {
                        Button { expanded.toggle() } label: {
                            HStack(spacing: 3) {
                                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("\(thread.count)")
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(expanded ? "Hide messages" : "Show each message")
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
        .onTapGesture { openInMail(thread.latest) }   // tapping opens the latest message in Mail
    }

    // A single message inside an expanded thread: direction + time + that message's own summary.
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
        for message in thread.messages {
            message.summary = nil
            message.summaryState = EmailSummaryState.pending.rawValue
        }
    }

    // Thread importance writes every message so the thread's max stays consistent.
    private func setImportance(_ importance: EmailImportance) {
        for message in thread.messages { message.importance = importance }
    }

    private func openInMail(_ message: EmailMessage) {
        mailService.openMessage(message) { result in
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
