import SwiftUI
import SwiftData

// A thread-grouped email digest for one activity scope (a focus block's emails, or the standalone
// out-of-block set). One bullet per conversation showing its whole-thread day summary + person/project
// chips + a sent/received breakdown. Expanding a bullet reveals its messages: sent messages keep their
// full time-logging row (SentEmailActivityRow → TimeLedger); received messages are informational.
struct EmailDigestGroupRow: View {
    var emails: [EmailMessage]
    @Query private var threadSummaries: [EmailThreadSummary]

    private var threads: [EmailThread] {
        EmailThreadBuilder.threads(from: emails)
            .map { thread in
                var t = thread
                t.synthesizedSummary = EmailThreadBuilder.summaryText(for: thread, in: threadSummaries)
                return t
            }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(threads) { thread in
                EmailDigestBullet(thread: thread)
            }
        }
    }
}

private struct EmailDigestBullet: View {
    let thread: EmailThread
    @State private var expanded = false
    @State private var mailService = MailScriptService()
    @State private var openError: String?

    private var loggedHours: Double {
        thread.messages.flatMap(\.timeEntries).reduce(0.0) { $0 + $1.duration.hoursNormalized }
    }
    // Expandable when there is per-message detail worth showing (any sent message to time-log, or >1 message).
    private var canExpand: Bool {
        thread.messages.contains { $0.direction == .sent } || thread.count > 1
    }
    private var countText: String {
        var parts: [String] = []
        if thread.sentCount > 0 { parts.append("\(thread.sentCount) sent") }
        if thread.receivedCount > 0 { parts.append("\(thread.receivedCount) recv") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            bulletLine
            if expanded {
                ForEach(thread.messages, id: \.persistentModelID) { message in
                    if message.direction == .sent {
                        SentEmailActivityRow(email: message)
                    } else {
                        receivedRow(message)
                    }
                }
            }
        }
        .alert("Couldn't open email", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(openError ?? "") }
    }

    private var bulletLine: some View {
        HStack(alignment: .top, spacing: 6) {
            Color.clear.frame(width: 16, height: 1)   // block indent
            Text("•").foregroundStyle(AppTheme.mutedText)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: thread.sentCount > 0 && thread.receivedCount > 0 ? "arrow.up.arrow.down"
                          : (thread.direction == .sent ? "paperplane" : "envelope"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if let person = thread.person {
                        Chip(label: person.name, color: AppTheme.person)
                    }
                    ForEach(thread.projects, id: \.persistentModelID) { project in
                        Chip(label: project.name, color: AppTheme.project)
                    }
                    if !countText.isEmpty {
                        Text(countText).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if loggedHours > 0 {
                        Chip(label: TimeFormat.short(hours: loggedHours), color: AppTheme.duration)
                    }
                    if canExpand {
                        Button { expanded.toggle() } label: {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
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
        .padding(.leading).padding(.trailing).padding(.vertical, 1)
    }

    private func receivedRow(_ message: EmailMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "envelope").foregroundStyle(.tertiary).font(.system(size: 10)).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text("Received \(message.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
                EmailContentLine(subject: message.subject, summary: message.summary,
                                 isSummarizing: message.isSummarizing, font: .caption)
            }
        }
        .padding(.leading, 44).padding(.trailing).padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            mailService.openMessage(message) { if case .failure(let e) = $0 { openError = e.userMessage } }
        }
    }
}
