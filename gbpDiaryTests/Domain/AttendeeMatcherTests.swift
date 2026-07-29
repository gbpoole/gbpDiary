import Testing
import Foundation
@testable import gbpDiary

@Suite("AttendeeMatcher")
@MainActor
struct AttendeeMatcherTests {
    private let alice = PersonRef(id: UUID(), name: "Alice Smith", emails: ["alice@example.com", "a.smith@work.com"])
    private let bob = PersonRef(id: UUID(), name: "Bob Jones", emails: [])

    private var people: [PersonRef] { [alice, bob] }

    @Test func resolve_matchesByEmailCaseInsensitive() {
        let attendees = [CalendarAttendee(name: "A. Smith", email: "ALICE@example.com")]
        #expect(AttendeeMatcher.resolve(attendees: attendees, against: people) == [.matched(existingId: alice.id)])
    }

    @Test func resolve_matchesWhenEmailIsSecondaryInList() {
        // Alice's second (non-primary) email should still match.
        let attendees = [CalendarAttendee(name: "Someone Else", email: "A.Smith@work.com")]
        #expect(AttendeeMatcher.resolve(attendees: attendees, against: people) == [.matched(existingId: alice.id)])
    }

    @Test func resolve_matchesByExactNameWhenNoEmail() {
        let attendees = [CalendarAttendee(name: "bob jones", email: nil)]
        #expect(AttendeeMatcher.resolve(attendees: attendees, against: people) == [.matched(existingId: bob.id)])
    }

    @Test func resolve_emailTakesPrecedenceOverName() {
        // Name matches Bob, but the email matches Alice — email wins.
        let attendees = [CalendarAttendee(name: "Bob Jones", email: "alice@example.com")]
        #expect(AttendeeMatcher.resolve(attendees: attendees, against: people) == [.matched(existingId: alice.id)])
    }

    @Test func resolve_noMatch_createsWithNameAndEmail() {
        let attendees = [CalendarAttendee(name: "Carol Diaz", email: "Carol@Example.com")]
        #expect(AttendeeMatcher.resolve(attendees: attendees, against: people)
                == [.create(name: "Carol Diaz", email: "carol@example.com")])
    }

    @Test func resolve_noMatchNoName_createsWithEmailAsName() {
        let attendees = [CalendarAttendee(name: "  ", email: "dave@example.com")]
        #expect(AttendeeMatcher.resolve(attendees: attendees, against: people)
                == [.create(name: "dave@example.com", email: "dave@example.com")])
    }

    @Test func resolve_emptyAttendees_returnsEmpty() {
        #expect(AttendeeMatcher.resolve(attendees: [], against: people).isEmpty)
    }

    @Test func resolve_blankNameNoEmail_isSkipped() {
        let attendees = [CalendarAttendee(name: "   ", email: nil)]
        #expect(AttendeeMatcher.resolve(attendees: attendees, against: people).isEmpty)
    }

    @Test func resolve_duplicateAttendees_collapse() {
        let attendees = [
            CalendarAttendee(name: "Carol Diaz", email: "carol@example.com"),
            CalendarAttendee(name: "Carol D.", email: "CAROL@example.com"),
        ]
        #expect(AttendeeMatcher.resolve(attendees: attendees, against: people)
                == [.create(name: "Carol Diaz", email: "carol@example.com")])
    }

    @Test func resolve_excludingEmails_filtersOrganizer() {
        let attendees = [
            CalendarAttendee(name: "Alice Smith", email: "alice@example.com"),
            CalendarAttendee(name: "Me", email: "me@example.com"),
        ]
        let result = AttendeeMatcher.resolve(attendees: attendees, against: people,
                                             excludingEmails: ["ME@example.com"])
        #expect(result == [.matched(existingId: alice.id)])
    }
}
