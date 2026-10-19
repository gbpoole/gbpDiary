import Foundation

// Which email bodies a full export fetches from Mail, and what to record when one can't be had.
//
// Fetching is expensive: each body is a separate AppleScript round-trip on `MailScriptRunner`'s single
// serial thread, with no cancellation. Measured on the real store, a week held 154 non-dismissed messages
// of which 3 were accepted, 3 filed to a project and 0 carried logged time — so fetching everything would
// spend minutes retrieving mail that has nothing to do with the timesheet. Hence the relevance rule.
//
// Pure: it takes values, never models, so every decision here is unit-tested.
nonisolated enum TimesheetBodyScope {

    /// Worth fetching: the conversation is filed to a project, was accepted in triage, or has logged time.
    /// (Dismissed conversations never reach here — `TimesheetContentProjection` drops them already.)
    static func isRelevant(hasProject: Bool, isAccepted: Bool, loggedHours: Double) -> Bool {
        hasProject || isAccepted || loggedHours > 0
    }

    /// One conversation's fetchable messages, as values.
    struct Candidate: Equatable, Sendable {
        let conversationID: UUID
        let hasProject: Bool
        let isAccepted: Bool
        let loggedHours: Double
        /// `hasMessageID` is false when `EmailMessage.messageId` is blank — Mail cannot be queried for it.
        let messages: [Message]

        struct Message: Equatable, Sendable {
            let id: UUID
            let hasMessageID: Bool
        }
    }

    /// What to fetch, and the reason recorded against everything that won't be.
    struct Plan: Equatable, Sendable {
        /// In input order, de-duplicated.
        let requested: [UUID]
        let skipped: [UUID: TimesheetEmailBody]

        var isEmpty: Bool { requested.isEmpty }
    }

    static func plan(_ candidates: [Candidate]) -> Plan {
        var requested: [UUID] = []
        var skipped: [UUID: TimesheetEmailBody] = [:]
        var seen = Set<UUID>()

        for candidate in candidates {
            let relevant = isRelevant(hasProject: candidate.hasProject,
                                      isAccepted: candidate.isAccepted,
                                      loggedHours: candidate.loggedHours)
            for message in candidate.messages {
                guard seen.insert(message.id).inserted else { continue }
                if !relevant {
                    skipped[message.id] = .skippedNotRelevant
                } else if !message.hasMessageID {
                    // No Mail id to look up — skip without spending a round trip on a certain failure.
                    skipped[message.id] = .skippedNoMessageID
                } else {
                    requested.append(message.id)
                }
            }
        }
        return Plan(requested: requested, skipped: skipped)
    }

    /// Whether an error ends the whole run rather than one message. Permission and availability failures
    /// apply to every subsequent fetch, so continuing would produce the same error sixty times.
    static func isFatal(_ error: MailScriptError) -> Bool {
        switch error {
        case .permissionDenied, .mailUnavailable: return true
        case .scriptError: return false
        }
    }
}
