import Foundation

// Every fetched email is triaged before it reaches the diary. Three states, derived from two stored
// bools on EmailMessage (`dismissed`, `accepted`) so existing data migrates cleanly:
//   • unclassified — newly fetched, not yet triaged (shown only in the triage window)
//   • accepted     — kept → shown on the diary Email section
//   • dismissed    — hidden (manual, or auto from an excluded sender)
enum EmailTriageState: String, CaseIterable {
    case unclassified
    case accepted
    case dismissed

    var label: String {
        switch self {
        case .unclassified: "To triage"
        case .accepted:     "Accepted"
        case .dismissed:    "Dismissed"
        }
    }

    /// Derive the state from the two stored flags (dismissed wins).
    static func from(dismissed: Bool, accepted: Bool) -> EmailTriageState {
        if dismissed { return .dismissed }
        return accepted ? .accepted : .unclassified
    }
}

// The triage window's view buckets (mutually exclusive). Distinct from the stored `EmailTriageState`
// because a to-do'd email is still `accepted` but shown in its own **Tasks** bucket.
enum EmailTriageCategory: String, CaseIterable {
    case toTriage
    case accepted
    case tasks
    case dismissed

    var label: String {
        switch self {
        case .toTriage:  "To triage"
        case .accepted:  "Accepted"
        case .tasks:     "Tasks"
        case .dismissed: "Dismissed"
        }
    }

    /// Bucket an email: dismissed wins; else a linked to-do → Tasks; else accepted → Accepted; else To triage.
    static func classify(state: EmailTriageState, hasTasks: Bool) -> EmailTriageCategory {
        switch state {
        case .dismissed: return .dismissed
        case .accepted:  return hasTasks ? .tasks : .accepted
        case .unclassified: return hasTasks ? .tasks : .toTriage
        }
    }

    /// Bucket a whole thread from its messages' (state, hasTasks). Any unclassified message keeps the thread
    /// in **To triage** (so a conversation isn't cleared until every message is handled); else a linked
    /// to-do → **Tasks**; else any accepted → **Accepted**; else **Dismissed** (all dismissed).
    static func classifyThread(_ messages: [(state: EmailTriageState, hasTasks: Bool)]) -> EmailTriageCategory {
        if messages.isEmpty { return .toTriage }
        if messages.contains(where: { $0.state == .unclassified }) { return .toTriage }
        if messages.contains(where: { $0.hasTasks }) { return .tasks }
        if messages.contains(where: { $0.state == .accepted }) { return .accepted }
        return .dismissed
    }
}
