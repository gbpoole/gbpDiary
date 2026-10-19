import Foundation

// The candidate ORDER offered when filing a meeting to a project from the Minutes table's inline pill.
//
// Selection, search, chips and creation all come from the shared `FuzzyPickerField`; the only thing this
// adds is which projects it should offer first. There are ~57 active projects, so the likely answer — a
// project this meeting's attendees actually work on — is floated to the top, mirroring how
// `EmailProjectSuggestions` ranks a conversation's party's projects. Everything else follows in the
// caller's display order, and the picker's own fuzzy search covers the long tail.
//
// Completed projects are never offered as a NEW choice; one already attached still shows as a removable
// chip (the picker renders the selection itself), so a historical link can be seen and removed.
nonisolated enum MeetingProjectOptions {
    struct Option: Equatable, Identifiable, Sendable {
        let id: UUID
        let name: String
    }

    /// - Parameters:
    ///   - all: every project, in display order (the caller sorts by name).
    ///   - attendeeProjectIDs: projects the meeting's attendees are on, most relevant first.
    ///   - completedIDs: completed projects — excluded from the offer.
    ///   - suggestionLimit: how many attendee-derived projects may jump the queue.
    /// - Returns: the projects to offer, attendee-suggested first, then the rest; never already-selected,
    ///   never completed.
    static func candidates(selectedIDs: [UUID],
                           attendeeProjectIDs: [UUID],
                           all: [Option],
                           completedIDs: Set<UUID> = [],
                           suggestionLimit: Int = 5) -> [Option] {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var used = Set(selectedIDs).union(completedIDs)

        var suggested: [Option] = []
        for id in attendeeProjectIDs {
            guard let option = byID[id], used.insert(id).inserted else { continue }
            suggested.append(option)
            if suggested.count == suggestionLimit { break }
        }
        return suggested + all.filter { !used.contains($0.id) }
    }

    /// What the cell reads when nothing is attached — a stated value, not a blank cell, so there is
    /// something to click on the many meetings that have no project yet.
    static let emptyLabel = "No project"
}
