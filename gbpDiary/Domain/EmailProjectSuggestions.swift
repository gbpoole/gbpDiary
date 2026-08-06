import Foundation

// Suggests projects to file an email under — surfaced as tap-to-apply chips, never auto-applied.
// Pure and testable: the view maps its SwiftData entities to these light refs. Two deterministic
// signals are combined and ranked; an optional on-device AI pick (stored separately) is merged by the
// view. Already-assigned projects are excluded.
struct ProjectRef: Equatable { let id: UUID; let name: String }

enum EmailProjectSuggestions {
    /// Inputs for one email's suggestions.
    struct Input: Equatable {
        var assignedIDs: [UUID]        // projects already on this email (excluded from suggestions)
        var senderProjectIDs: [UUID]   // projects of the sender's linked Person (dev/sci teams)
        var priorProjectIDs: [UUID]    // projects on other emails from the same sender/thread
        var aiSuggestedID: UUID?       // optional on-device model pick
    }

    /// Ranked, de-duplicated suggestions (by id), resolved to the given projects, excluding assigned.
    /// Ranking: AI pick first, then projects seen in prior sender/thread emails (by frequency), then the
    /// sender's Person projects. Capped.
    static func rank(_ input: Input, projects: [ProjectRef], limit: Int = 3) -> [ProjectRef] {
        let assigned = Set(input.assignedIDs)
        let byID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })

        var score: [UUID: Int] = [:]
        var order: [UUID] = []
        func bump(_ id: UUID, by points: Int) {
            if score[id] == nil { order.append(id) }
            score[id, default: 0] += points
        }
        if let ai = input.aiSuggestedID { bump(ai, by: 100) }
        for id in input.priorProjectIDs { bump(id, by: 10) }   // repeats accumulate (frequency)
        for id in input.senderProjectIDs { bump(id, by: 1) }

        return order
            .filter { !assigned.contains($0) && byID[$0] != nil }
            .sorted { (score[$0] ?? 0, orderIndex($0, order)) > (score[$1] ?? 0, orderIndex($1, order)) }
            .prefix(limit)
            .compactMap { byID[$0] }
    }

    // Stable tiebreaker: earlier-first among equal scores (negate so higher tuple = earlier).
    private static func orderIndex(_ id: UUID, _ order: [UUID]) -> Int {
        -(order.firstIndex(of: id) ?? Int.max)
    }
}
