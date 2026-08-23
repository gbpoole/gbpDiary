import Foundation
import Testing
@testable import gbpDiary

struct EmailThreadFoldTests {
    private func s(_ accepted: Bool, _ dismissed: Bool, _ imp: EmailImportance = .low) -> EmailThreadFold.MemberState {
        .init(accepted: accepted, dismissed: dismissed, importance: imp)
    }

    @Test func anyUnclassifiedKeepsConversationToTriage() {
        let f = EmailThreadFold.fold([s(true, false), s(false, false)])   // one accepted, one unclassified
        #expect(f.accepted == false)
        #expect(f.dismissed == false)
    }

    @Test func anyAcceptedWhenNoneUnclassified() {
        let f = EmailThreadFold.fold([s(true, false), s(false, true)])   // accepted + dismissed, none pending
        #expect(f.accepted == true)
        #expect(f.dismissed == false)
    }

    @Test func allDismissed() {
        let f = EmailThreadFold.fold([s(false, true), s(false, true)])
        #expect(f.accepted == false)
        #expect(f.dismissed == true)
    }

    @Test func importanceIsMaxAcrossMembers() {
        let f = EmailThreadFold.fold([s(true, false, .low), s(true, false, .high), s(true, false, .medium)])
        #expect(f.importance == .high)
    }

    @Test func emptyIsUnclassifiedLow() {
        let f = EmailThreadFold.fold([])
        #expect(f.accepted == false)
        #expect(f.dismissed == false)
        #expect(f.importance == .low)
    }
}
