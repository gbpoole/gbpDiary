import Testing
import Foundation
@testable import gbpDiary

@Suite("EmailRetention")
struct EmailRetentionTests {
    private let now = FixedDates.reference
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: now)! }

    @Test func dismissedAndOld_isPurgeable() {
        #expect(EmailRetention.isPurgeable(dismissed: true, latestDate: daysAgo(31), now: now, days: 30))
    }

    @Test func dismissedButRecent_isKept() {
        #expect(!EmailRetention.isPurgeable(dismissed: true, latestDate: daysAgo(10), now: now, days: 30))
    }

    @Test func oldButNotDismissed_isKept() {
        #expect(!EmailRetention.isPurgeable(dismissed: false, latestDate: daysAgo(90), now: now, days: 30))
    }

    @Test func noLatestDate_isKept() {
        #expect(!EmailRetention.isPurgeable(dismissed: true, latestDate: nil, now: now, days: 30))
    }

    @Test func exactlyAtCutoff_isKept() {
        // latest == cutoff is not strictly older, so it's kept.
        #expect(!EmailRetention.isPurgeable(dismissed: true, latestDate: daysAgo(30), now: now, days: 30))
    }
}
