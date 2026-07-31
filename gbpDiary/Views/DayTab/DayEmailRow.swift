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
    let allProjects: [Project]
    let onReconcile: () -> Void
    let makeProject: (String) -> Project?

    @State private var mailService = MailScriptService()
    @State private var openError: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { openInMail() } label: {
                Image(systemName: thread.direction == .sent ? "paperplane" : "envelope")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help("Open in Mail")
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    personChip
                    projectPicker
                    Spacer(minLength: 0)
                    if thread.count > 1 {
                        Chip(label: "\(thread.count)", color: .gray)
                    }
                    Text(thread.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(thread.subject)
                    .font(.callout)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .alert("Couldn't open email", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(openError ?? "") }
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

    // Compact (icon-style) project picker: shows project chips + a small add button; edits all messages.
    private var projectPicker: some View {
        FuzzyPickerField(
            allItems: allProjects,
            selected: Binding(
                get: { thread.projects },
                set: { newValue in for m in thread.messages { m.projects = newValue } }
            ),
            label: \.name,
            chipColor: AppTheme.project,
            onCreateItem: makeProject
        )
    }
}
