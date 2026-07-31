import SwiftUI
import SwiftData

// Identifiable wrapper so a fetched batch can drive a `.sheet(item:)`.
struct EmailIngestRequest: Identifiable {
    let id = UUID()
    let drafts: [MailMessageDraft]
    let account: String
}

// Shown after a manual email refresh, before anything is stored. Lists the freshly-fetched emails
// cross-referenced with what's already in the store: previously-ingested ones start selected (and
// highlighted), previously-skipped ones start unselected (marked "Previously skipped"), and new ones
// are marked "New". The user toggles which to ingest; on confirm the decisions are applied — and
// remembered (skipped emails are stored dismissed) so a later refresh shows the same state.
struct EmailIngestSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let day: Date
    let drafts: [MailMessageDraft]
    let account: String

    @Query(sort: \EmailMessage.date, order: .reverse) private var allEmails: [EmailMessage]
    @Query private var allPeople: [Person]

    @State private var selection: Set<String> = []
    @State private var didInit = false

    private var candidates: [EmailIngestCandidate] {
        EmailIngestPlanning.candidates(drafts: drafts, account: account, existing: existingMap())
            .sorted { $0.draft.date > $1.draft.date }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlBar
                Divider()
                if candidates.isEmpty {
                    Text("No email found for this day.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selection) {
                        ForEach(candidates) { candidate in
                            EmailIngestRow(candidate: candidate)
                        }
                    }
                }
            }
            .navigationTitle("Update Email — \(day.formatted(date: .abbreviated, time: .omitted))")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update (\(selection.count))") { apply(); dismiss() }
                }
            }
        }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            selection = Set(candidates.filter(\.defaultSelected).map(\.key))
        }
        #if os(macOS)
        .frame(minWidth: 660, minHeight: 500)
        #endif
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            let newCount = candidates.filter { $0.state == .new }.count
            Text("\(candidates.count) fetched\(newCount > 0 ? " · \(newCount) new" : "")")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Select all") { selection = Set(candidates.map(\.key)) }
            Button("Select none") { selection.removeAll() }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    // MARK: - Data

    private func existingMap() -> [String: Bool] {
        let cal = Calendar.current
        var map: [String: Bool] = [:]
        for e in allEmails where cal.isDate(e.date, inSameDayAs: day) {
            let key = MailScriptParsing.dedupeKey(messageId: e.messageId, account: e.account, mailbox: e.mailbox,
                                                  date: e.date, fromAddress: e.fromAddress, subject: e.subject)
            map[key] = e.dismissed
        }
        return map
    }

    private func existingEmail(forKey key: String) -> EmailMessage? {
        let cal = Calendar.current
        return allEmails.first { e in
            guard cal.isDate(e.date, inSameDayAs: day) else { return false }
            let k = MailScriptParsing.dedupeKey(messageId: e.messageId, account: e.account, mailbox: e.mailbox,
                                                date: e.date, fromAddress: e.fromAddress, subject: e.subject)
            return k == key
        }
    }

    // Apply the user's choices. Selected → ingested (dismissed = false); unselected → remembered as
    // skipped (dismissed = true) so a later refresh shows the same state and decisions aren't repeated.
    private func apply() {
        let peopleRefs = allPeople.map { PersonRef(id: $0.id, name: $0.name, emails: $0.emails) }
        for candidate in candidates {
            let keep = selection.contains(candidate.key)
            switch candidate.state {
            case .new:
                insert(candidate.draft, dismissed: !keep, peopleRefs: peopleRefs)
            case .ingested, .notChosen:
                if let email = existingEmail(forKey: candidate.key) { email.dismissed = !keep }
            }
        }
    }

    private func insert(_ d: MailMessageDraft, dismissed: Bool, peopleRefs: [PersonRef]) {
        let mailbox = EmailIngestPlanning.mailbox(for: d.direction)
        let msg = EmailMessage(messageId: d.messageId, account: account, mailbox: mailbox,
                               direction: d.direction, fromAddress: d.address, fromName: d.name,
                               subject: d.subject, date: d.date)
        msg.dismissed = dismissed
        modelContext.insert(msg)
        if let personID = EmailPersonMatching.personID(forAddress: d.address, in: peopleRefs),
           let person = allPeople.first(where: { $0.id == personID }) {
            msg.person = person
        }
    }
}

// One fetched email in the ingest list: direction icon, sender/subject/time, and a status chip
// (New / Previously skipped / Ingested). Selection highlight indicates it will be ingested.
private struct EmailIngestRow: View {
    let candidate: EmailIngestCandidate

    private var draft: MailMessageDraft { candidate.draft }
    private var sender: String {
        if let name = draft.name, !name.isEmpty { return name }
        return draft.address.isEmpty ? "Unknown sender" : draft.address
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: draft.direction == .sent ? "paperplane" : "envelope")
                .foregroundStyle(.secondary).font(.system(size: 14)).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(sender).lineLimit(1).fontWeight(.medium)
                    if draft.direction == .sent { Chip(label: "Sent", color: .gray) }
                    statusChip
                    Spacer(minLength: 0)
                    Text(draft.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(draft.subject.isEmpty ? "(no subject)" : draft.subject)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var statusChip: some View {
        switch candidate.state {
        case .new:       Chip(label: "New", color: AppTheme.accent)
        case .notChosen: Chip(label: "Previously skipped", color: .gray)
        case .ingested:  Chip(label: "Ingested", color: AppTheme.person)
        }
    }
}
