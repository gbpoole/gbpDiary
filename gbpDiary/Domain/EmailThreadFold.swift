import Foundation

// Rolls a set of member messages' triage state + importance up into the conversation's state — used by the
// one-time migration (folding legacy per-message state onto the new EmailConversation) and anywhere a
// conversation's state is derived from its messages. Project/person rollups need @Model access, so they
// live in the migration; this is the pure, testable part. Mirrors `EmailTriageCategory.classifyThread`:
// any unclassified member keeps the conversation in To-triage; else any accepted → accepted; else dismissed.
nonisolated enum EmailThreadFold {
    struct MemberState: Equatable, Sendable {
        let accepted: Bool
        let dismissed: Bool
        let importance: EmailImportance
        init(accepted: Bool, dismissed: Bool, importance: EmailImportance = .low) {
            self.accepted = accepted
            self.dismissed = dismissed
            self.importance = importance
        }
        var isUnclassified: Bool { !accepted && !dismissed }
    }

    struct Folded: Equatable, Sendable {
        let accepted: Bool
        let dismissed: Bool
        let importance: EmailImportance
    }

    static func fold(_ members: [MemberState]) -> Folded {
        guard !members.isEmpty else { return Folded(accepted: false, dismissed: false, importance: .low) }
        let importance = members.map(\.importance).max(by: { $0.rank < $1.rank }) ?? .low
        if members.contains(where: { $0.isUnclassified }) {
            return Folded(accepted: false, dismissed: false, importance: importance)   // to triage
        }
        if members.contains(where: { $0.accepted }) {
            return Folded(accepted: true, dismissed: false, importance: importance)
        }
        return Folded(accepted: false, dismissed: true, importance: importance)          // all dismissed
    }
}
