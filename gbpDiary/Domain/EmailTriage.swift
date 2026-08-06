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
