import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct JSONHelpersTests {
    @Test func jsonEncodeDecode_roundTripsStringArray() {
        let input = ["alpha", "beta"]
        let encoded = jsonEncode(input)
        let decoded = jsonDecode([String].self, encoded)
        #expect(decoded == input)
    }

    @Test func jsonDecode_invalidJson_returnsNil() {
        let decoded = jsonDecode([String].self, "not json")
        #expect(decoded == nil)
    }

    @Test func taskTagsAndHistory_defaultToEmptyOnInvalidJson() {
        let task = Task(summary: "x")
        task.tagsJSON = "bad"
        task.followedUpHistoryJSON = "bad"

        #expect(task.tags.isEmpty)
        #expect(task.followedUpHistory.isEmpty)
    }

    @Test func noteTags_roundTripViaJsonStorage() {
        let note = Note(content: "summary")
        note.tags = ["swift", "diary"]
        #expect(note.tags == ["swift", "diary"])
    }

    @Test func noteTags_defaultToEmptyOnInvalidJson() {
        let note = Note(content: "x")
        note.tagsJSON = "bad"
        #expect(note.tags.isEmpty)
    }
}
