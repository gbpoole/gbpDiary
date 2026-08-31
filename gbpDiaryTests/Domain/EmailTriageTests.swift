import Testing
import Foundation
@testable import gbpDiary

@Suite("EmailTriage")
struct EmailTriageTests {
    @Test func state_dismissedWins() {
        #expect(EmailTriageState.from(dismissed: true, accepted: true) == .dismissed)
        #expect(EmailTriageState.from(dismissed: true, accepted: false) == .dismissed)
    }

    @Test func state_acceptedThenUnclassified() {
        #expect(EmailTriageState.from(dismissed: false, accepted: true) == .accepted)
        #expect(EmailTriageState.from(dismissed: false, accepted: false) == .unclassified)
    }

    @Test func category_classify_bucketsByStateAndTasks() {
        // Dismissed wins regardless of tasks.
        #expect(EmailTriageCategory.classify(state: .dismissed, hasTasks: false) == .dismissed)
        #expect(EmailTriageCategory.classify(state: .dismissed, hasTasks: true) == .dismissed)
        // Accepted splits by whether it has a to-do.
        #expect(EmailTriageCategory.classify(state: .accepted, hasTasks: false) == .accepted)
        #expect(EmailTriageCategory.classify(state: .accepted, hasTasks: true) == .tasks)
        // Unclassified with a to-do still surfaces under Tasks; otherwise To triage.
        #expect(EmailTriageCategory.classify(state: .unclassified, hasTasks: false) == .toTriage)
        #expect(EmailTriageCategory.classify(state: .unclassified, hasTasks: true) == .tasks)
    }

    @Test func classifyThread_bucketsAWholeThread() {
        // Any unclassified message keeps the whole thread in To triage.
        #expect(EmailTriageCategory.classifyThread([(.accepted, false), (.unclassified, false)]) == .toTriage)
        // No unclassified + a linked to-do → Tasks.
        #expect(EmailTriageCategory.classifyThread([(.accepted, true), (.accepted, false)]) == .tasks)
        // No unclassified, no tasks, any accepted → Accepted.
        #expect(EmailTriageCategory.classifyThread([(.accepted, false), (.dismissed, false)]) == .accepted)
        // All dismissed → Dismissed.
        #expect(EmailTriageCategory.classifyThread([(.dismissed, false), (.dismissed, false)]) == .dismissed)
        // Empty → To triage.
        #expect(EmailTriageCategory.classifyThread([]) == .toTriage)
    }

    // MARK: - Incremental fetch bounds

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func fetchBounds_firstRun_usesFullWindow() {
        let now = at(2026, 7, 30, 9, 0)
        let b = EmailIngest.fetchBounds(lastFetchedAt: nil, now: now, calendar: cal)
        #expect(b.start == at(2026, 7, 28))          // 3-day window: today − 2
        #expect(b.end == at(2026, 7, 31))            // start of tomorrow
    }

    @Test func fetchBounds_incremental_startsJustBeforeLastFetch() {
        let now = at(2026, 7, 30, 9, 0)
        let last = at(2026, 7, 30, 8, 50)            // 10 min ago
        let b = EmailIngest.fetchBounds(lastFetchedAt: last, now: now, calendar: cal)
        // start = last − overlap(600s) = 08:40; within the window, so used as-is.
        #expect(b.start == at(2026, 7, 30, 8, 40))
        #expect(b.end == at(2026, 7, 31))
    }

    @Test func fetchBounds_longGap_clampsToWindowStart() {
        let now = at(2026, 7, 30, 9, 0)
        let last = at(2026, 7, 1)                     // weeks ago
        let b = EmailIngest.fetchBounds(lastFetchedAt: last, now: now, calendar: cal)
        #expect(b.start == at(2026, 7, 28))           // clamped to the 3-day window start
    }
}
