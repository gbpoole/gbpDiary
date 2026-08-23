import SwiftUI
import SwiftData
import Combine
import OSLog

// Shared ingest: insert fetched drafts that aren't already stored. Excluded senders are dismissed on
// arrival (future-only); the "other party" is auto-linked when the address already belongs to a Person.
@MainActor
enum EmailIngest {
    static let daysBack = 3
    static let overlap: TimeInterval = 600   // re-scan the last 10 min so boundary emails aren't missed

    /// The half-open fetch window for "the last `daysBack` days" ending today (start-of-day bounds).
    nonisolated static func window(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date) {
        let startOfToday = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(daysBack - 1), to: startOfToday) ?? startOfToday
        let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        return (start, end)
    }

    /// Incremental fetch bounds: from just before the last fetch (with `overlap`) to end-of-today,
    /// clamped to the `daysBack` window so a long gap doesn't scan a huge range. First run (nil) uses
    /// the full window.
    nonisolated static func fetchBounds(lastFetchedAt: Date?, now: Date = Date(),
                                        calendar: Calendar = .current) -> (start: Date, end: Date) {
        let win = window(now: now, calendar: calendar)
        guard let last = lastFetchedAt else { return win }
        let start = max(win.start, last.addingTimeInterval(-overlap))
        return (min(start, win.end), win.end)
    }

    /// Insert drafts not already present (dedupe by Mail's per-message key). Returns the count added.
    @discardableResult
    static func upsert(_ drafts: [MailMessageDraft], account: String,
                       existing: [EmailMessage], people: [Person], context: ModelContext) -> Int {
        var keys = Set(existing.map {
            MailScriptParsing.dedupeKey(messageId: $0.messageId, account: $0.account, mailbox: $0.mailbox,
                                        date: $0.date, fromAddress: $0.fromAddress, subject: $0.subject)
        })
        let rules = EmailExcludeStore.load()
        let refs = people.map { PersonRef(id: $0.id, name: $0.name, emails: $0.emails) }

        // Mailing-list loopbacks: a received email whose sender is one of the "Me" person's own
        // addresses is really your own outgoing mail bounced back. Skip new ones and dismiss any that
        // slipped in before (self-heals as your identity/addresses change).
        let myAddresses = EmailSelfMatching.normalizedAddresses(
            AppSettingsStore.myPersonID.flatMap { id in people.first { $0.id == id }?.emails } ?? [])
        if !myAddresses.isEmpty {
            for e in existing where !e.dismissed
                && EmailSelfMatching.isInboxFromSelf(direction: e.direction,
                                                     fromAddress: e.fromAddress, myAddresses: myAddresses) {
                e.triageDismiss()
            }
        }

        var added = 0
        var inserted: [EmailMessage] = []
        for d in drafts {
            let mailbox = EmailIngestPlanning.mailbox(for: d.direction)
            let key = MailScriptParsing.dedupeKey(messageId: d.messageId, account: account, mailbox: mailbox,
                                                  date: d.date, fromAddress: d.address, subject: d.subject)
            guard keys.insert(key).inserted else { continue }
            if EmailSelfMatching.isInboxFromSelf(direction: d.direction, fromAddress: d.address,
                                                 myAddresses: myAddresses) { continue }
            let msg = EmailMessage(messageId: d.messageId, account: account, mailbox: mailbox,
                                   direction: d.direction, fromAddress: d.address, fromName: d.name,
                                   subject: d.subject, date: d.date)
            msg.rfcMessageId = d.rfcMessageId    // reply-chain headers → threading
            msg.inReplyTo = d.inReplyTo
            msg.references = d.references
            // Matches a spam rule → dismissed; everything else (sent + received) → unclassified, so sent
            // mail is actively triaged (file project / log time / accept) on the Emails page like received.
            if EmailExcludeMatching.isExcluded(fromAddress: d.address, subject: d.subject, rules: rules) {
                msg.dismissed = true
            }
            context.insert(msg)
            if let pid = EmailPersonMatching.personID(forAddress: d.address, in: refs),
               let p = people.first(where: { $0.id == pid }) {
                msg.person = p
            }
            inserted.append(msg)
            added += 1
        }
        // Attach new mail to its conversation (reply-graph threaded), creating/merging as needed.
        if !inserted.isEmpty {
            EmailConversationReconciler.reconcile(emails: existing + inserted, context: context)
        }
        return added
    }
}

// Persists the last successful fetch time so subsequent fetches are incremental.
enum EmailFetchStateStore {
    private static let key = "email.lastFetchedAt"
    static func lastFetchedAt(_ d: UserDefaults = .standard) -> Date? {
        let t = d.double(forKey: key)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    static func setLastFetchedAt(_ date: Date, _ d: UserDefaults = .standard) {
        d.set(date.timeIntervalSince1970, forKey: key)
    }
}

// Invisible, global driver (placed once in WorkspaceView): fetches the last few days of email from
// Mail automatically on a 5-minute cadence (and on appear), so the diary stays current without a
// manual trigger. The AppleScript runs on the main thread (Mail requirement) but only every 5 min.
struct EmailFetchDriver: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \EmailMessage.date, order: .reverse) private var allEmails: [EmailMessage]
    @Query private var allPeople: [Person]
    @State private var service = MailScriptService()
    @State private var isFetching = false
    private let log = Logger(subsystem: "gbpDiary", category: "EmailFetch")

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { migrateTriageOnce() }   // runs before the fetch task
            .task { fetchNow() }                // initial catch-up on launch
            .onReceive(Timer.publish(every: 300, on: .main, in: .common).autoconnect()) { _ in
                fetchNow()
            }
    }

    // One-time: pre-existing non-dismissed emails predate triage — mark them accepted so they stay on
    // the diary (rather than flooding the triage inbox as "unclassified").
    private func migrateTriageOnce() {
        let key = "email.triageMigrated.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for e in allEmails where !e.dismissed && !e.accepted { e.accepted = true }
        UserDefaults.standard.set(true, forKey: key)
    }

    private func fetchNow() {
        guard !isFetching else { return }
        let settings = EmailSettingsStore.load()
        guard settings.isConfigured else { return }
        isFetching = true
        let bounds = EmailIngest.fetchBounds(lastFetchedAt: EmailFetchStateStore.lastFetchedAt())
        service.fetchRange(rangeStart: bounds.start, rangeEnd: bounds.end, settings: settings) { result in
            isFetching = false
            switch result {
            case .success(let drafts):
                let added = EmailIngest.upsert(drafts, account: settings.accountName,
                                               existing: allEmails, people: allPeople, context: modelContext)
                EmailFetchStateStore.setLastFetchedAt(Date())
                if added > 0 { log.notice("Auto-ingested \(added, privacy: .public) email(s)") }
            case .failure(let error):
                log.error("Auto-ingest failed: \(error.userMessage, privacy: .public)")
            }
        }
    }
}
