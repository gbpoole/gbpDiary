import Foundation

// Classifies freshly-fetched Mail drafts against what's already in the store so the ingest window can
// show, for each fetched email, whether it was previously ingested (kept), previously skipped
// (dismissed), or is new. Pure and testable; the view supplies the existing keys and applies the
// user's selection afterwards.
enum EmailIngestState: Equatable {
    case new         // not seen before
    case ingested    // previously ingested and kept (dismissed == false)
    case notChosen   // previously fetched but skipped (dismissed == true)
}

struct EmailIngestCandidate: Identifiable, Equatable {
    let key: String                 // dedupe key (matches EmailMessage)
    let draft: MailMessageDraft
    let state: EmailIngestState
    var id: String { key }
    /// New and previously-ingested emails start selected; previously-skipped start unselected.
    var defaultSelected: Bool { state != .notChosen }
}

enum EmailIngestPlanning {
    /// The stored mailbox name for a draft's direction (mirrors DayView.upsertEmails).
    static func mailbox(for direction: EmailDirection) -> String {
        direction == .inbox ? "INBOX" : "Sent"
    }

    /// Classify each draft. `existing` maps a dedupe key to its stored `dismissed` flag.
    static func candidates(drafts: [MailMessageDraft], account: String,
                           existing: [String: Bool]) -> [EmailIngestCandidate] {
        drafts.map { d in
            let key = MailScriptParsing.dedupeKey(
                messageId: d.messageId, account: account, mailbox: mailbox(for: d.direction),
                date: d.date, fromAddress: d.address, subject: d.subject)
            let state: EmailIngestState
            if let dismissed = existing[key] { state = dismissed ? .notChosen : .ingested }
            else { state = .new }
            return EmailIngestCandidate(key: key, draft: d, state: state)
        }
    }
}
