import Foundation

// Turns the already-built `FullContent` into a body-fetch plan.
//
// It derives from the CONTENT, not by re-walking the models, which is the structural guarantee that every
// message appearing in the exported tree has an outcome recorded, and that no fetch is issued for a message
// that isn't in the tree. (The same discipline as `TimesheetProjection` reading the ledger's own filtered
// inputs rather than re-deriving them.)
@MainActor
enum TimesheetBodyPlanProjection {

    struct Resolved {
        let plan: TimesheetBodyScope.Plan
        /// The `EmailMessage` to fetch, in plan order. Looked up once so the run needs no further queries.
        let messages: [EmailMessage]
    }

    static func resolve(content: TimesheetExportSnapshot.FullContent,
                        conversations: [EmailConversation],
                        emails: [EmailMessage]) -> Resolved {
        let acceptedByID = Dictionary(conversations.map { ($0.id, $0.triageState == .accepted) },
                                      uniquingKeysWith: { a, _ in a })
        let messagesByID = Dictionary(emails.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        let candidates = content.conversations.map { conversation in
            TimesheetBodyScope.Candidate(
                conversationID: conversation.id,
                hasProject: !conversation.projects.isEmpty,
                isAccepted: acceptedByID[conversation.id] ?? false,
                loggedHours: conversation.loggedHours,
                messages: conversation.messages.map { message in
                    .init(id: message.id,
                          hasMessageID: !(messagesByID[message.id]?.messageId ?? "")
                              .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                })
        }

        let plan = TimesheetBodyScope.plan(candidates)
        return Resolved(plan: plan, messages: plan.requested.compactMap { messagesByID[$0] })
    }
}
