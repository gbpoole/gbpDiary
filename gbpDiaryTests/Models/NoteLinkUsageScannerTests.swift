import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct NoteLinkUsageScannerTests {

    @Test func backlinks_findsReferrers() {
        let target = UUID(); let a = UUID(); let b = UUID(); let c = UUID()
        let notes: [(id: UUID, content: String)] = [
            (a, "links to [T](note://\(target.uuidString))"),
            (b, "no links here"),
            (c, "also [T](note://\(target.uuidString)) referenced"),
        ]
        #expect(NoteLinkUsageScanner.backlinks(to: target, in: notes) == [a, c])
    }

    @Test func backlinks_excludesSelfReference() {
        let target = UUID()
        let notes: [(id: UUID, content: String)] = [
            (target, "I link to myself [me](note://\(target.uuidString))"),
        ]
        #expect(NoteLinkUsageScanner.backlinks(to: target, in: notes).isEmpty)
    }

    @Test func backlinks_emptyWhenNoReferrers() {
        let target = UUID(); let a = UUID()
        let notes: [(id: UUID, content: String)] = [(a, "unrelated content")]
        #expect(NoteLinkUsageScanner.backlinks(to: target, in: notes).isEmpty)
    }
}

@MainActor
struct NoteContentMembershipTests {

    @Test func isContentNote_requiresNonEmptyTitle() {
        #expect(NoteContentMembership.isContentNote(title: "Idea", hasDayRecord: false, hasMinutes: false))
        #expect(!NoteContentMembership.isContentNote(title: "", hasDayRecord: false, hasMinutes: false))
        #expect(!NoteContentMembership.isContentNote(title: "   ", hasDayRecord: false, hasMinutes: false))
    }

    @Test func isContentNote_excludesDayAndMeetingNotes() {
        #expect(!NoteContentMembership.isContentNote(title: "Idea", hasDayRecord: true, hasMinutes: false))
        #expect(!NoteContentMembership.isContentNote(title: "Idea", hasDayRecord: false, hasMinutes: true))
    }
}
