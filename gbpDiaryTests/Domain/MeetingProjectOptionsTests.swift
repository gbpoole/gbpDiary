import Foundation
import Testing
@testable import gbpDiary

// Selection, search and chips come from the shared `FuzzyPickerField`; what's tested here is the only thing
// this helper decides — WHICH projects the inline meeting picker offers, and in what order.
struct MeetingProjectOptionsTests {
    private func opt(_ name: String, _ id: UUID = UUID()) -> MeetingProjectOptions.Option {
        .init(id: id, name: name)
    }
    private func names(_ options: [MeetingProjectOptions.Option]) -> [String] { options.map(\.name) }

    @Test func attendeeProjectsAreOfferedFirst_thenTheRestInDisplayOrder() {
        let alpha = opt("Alpha"), beta = opt("Beta"), gamma = opt("Gamma")
        let offered = MeetingProjectOptions.candidates(selectedIDs: [],
                                                       attendeeProjectIDs: [gamma.id],
                                                       all: [alpha, beta, gamma])
        #expect(names(offered) == ["Gamma", "Alpha", "Beta"])
    }

    @Test func noSuggestions_keepsTheCallersOrder() {
        let all = [opt("Alpha"), opt("Beta"), opt("Gamma")]
        #expect(names(MeetingProjectOptions.candidates(selectedIDs: [], attendeeProjectIDs: [], all: all))
                == ["Alpha", "Beta", "Gamma"])
    }

    // The picker renders the selection itself as removable chips, so an attached project is not re-offered.
    @Test func alreadyAttachedProjectsAreNotOffered() {
        let a = opt("A"), b = opt("B")
        let offered = MeetingProjectOptions.candidates(selectedIDs: [a.id],
                                                       attendeeProjectIDs: [a.id, b.id],
                                                       all: [a, b])
        #expect(names(offered) == ["B"])
    }

    @Test func eachProjectIsOfferedOnce() {
        let a = opt("A"), b = opt("B")
        let offered = MeetingProjectOptions.candidates(selectedIDs: [],
                                                       attendeeProjectIDs: [b.id, b.id],   // overlapping attendees
                                                       all: [a, b])
        #expect(names(offered) == ["B", "A"])
    }

    @Test func suggestionsAreCapped() {
        let all = (1...8).map { opt("P\($0)") }
        let offered = MeetingProjectOptions.candidates(selectedIDs: [],
                                                       attendeeProjectIDs: all.map(\.id),
                                                       all: all, suggestionLimit: 3)
        // The first three jump the queue; the rest follow in display order, nothing duplicated or lost.
        #expect(names(offered) == ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8"])
        #expect(offered.count == all.count)
    }

    // A finished project is not a place to newly file a meeting; one already attached stays visible as a
    // chip (the picker owns the selection), so a historical link can still be removed.
    @Test func completedProjectsAreNeverOffered() {
        let live = opt("Live"), done = opt("Done")
        let offered = MeetingProjectOptions.candidates(selectedIDs: [],
                                                       attendeeProjectIDs: [done.id],
                                                       all: [done, live],
                                                       completedIDs: [done.id])
        #expect(names(offered) == ["Live"])
    }

    @Test func unknownAttendeeProjectIdsAreIgnored() {
        let a = opt("A")
        let offered = MeetingProjectOptions.candidates(selectedIDs: [], attendeeProjectIDs: [UUID()], all: [a])
        #expect(names(offered) == ["A"])
    }

    @Test func emptyInputs_offerNothing() {
        #expect(MeetingProjectOptions.candidates(selectedIDs: [], attendeeProjectIDs: [], all: []).isEmpty)
    }

    // Many meetings have no project, so the cell must still state a value to click.
    @Test func emptyLabelIsStated() {
        #expect(MeetingProjectOptions.emptyLabel == "No project")
    }
}
