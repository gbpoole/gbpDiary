import Foundation
import Testing
@testable import gbpDiary

struct ProjectActivityTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func lastActivityAt_nilWhenNoWork() {
        #expect(ProjectActivity.lastActivityAt(timeEntryDates: [], focusBlockDates: []) == nil)
    }

    @Test func lastActivityAt_isMaxAcrossBothSources() {
        let a = t0
        let b = t0.addingTimeInterval(3600)
        let c = t0.addingTimeInterval(7200)
        #expect(ProjectActivity.lastActivityAt(timeEntryDates: [a, b], focusBlockDates: [c]) == c)
        #expect(ProjectActivity.lastActivityAt(timeEntryDates: [c], focusBlockDates: [a]) == c)
    }

    @Test func lastActivityAt_usesTimeEntriesWhenNoBlocks() {
        let b = t0.addingTimeInterval(3600)
        #expect(ProjectActivity.lastActivityAt(timeEntryDates: [t0, b], focusBlockDates: []) == b)
    }
}
