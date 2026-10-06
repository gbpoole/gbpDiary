import Testing
import Foundation
@testable import gbpDiary

@Suite("FollowUpHistory")
struct FollowUpHistoryTests {
    private let cal = Calendar.current
    private func day(_ offset: Int) -> Date { FixedDates.dayStart(offsetDays: offset) }
    private func afternoon(_ offset: Int) -> Date { day(offset).addingTimeInterval(14 * 3_600) }

    // MARK: - Day granularity

    @Test func day_stripsTheTimeOfDay() {
        #expect(FollowUpHistory.day(afternoon(0)) == day(0))
        #expect(FollowUpHistory.day(day(3)) == day(3), "already a day start — unchanged")
    }

    /// Today counts; yesterday does not. This is the whole "a follow-up today just means today" rule.
    @Test func isDateAllowed_todayOnwardOnly() {
        let now = afternoon(0)
        #expect(FollowUpHistory.isDateAllowed(day(0), now: now))
        #expect(FollowUpHistory.isDateAllowed(afternoon(0), now: now))
        #expect(FollowUpHistory.isDateAllowed(day(1), now: now))
        #expect(!FollowUpHistory.isDateAllowed(day(-1), now: now))
    }

    /// Both verbs share one gate: a real reason, and a date that isn't in the past.
    @Test func canSave_needsANoteAndANonPastDate() {
        let now = afternoon(0)
        #expect(FollowUpHistory.canSave(note: "waiting on Sam", date: day(1), now: now))
        #expect(!FollowUpHistory.canSave(note: "", date: day(1), now: now))
        #expect(!FollowUpHistory.canSave(note: "   \n ", date: day(1), now: now), "whitespace is not a reason")
        #expect(!FollowUpHistory.canSave(note: "waiting", date: day(-1), now: now))
    }

    // MARK: - Ordering

    /// Display is date-descending so the list reads as a timeline even after a back-dated correction —
    /// append order (which decides what is *pending*) is a separate concern.
    @Test func displayOrder_isNewestDatedFirst_regardlessOfAppendOrder() {
        let a = FollowUpEntry(date: day(1), note: "a")
        let b = FollowUpEntry(date: day(9), note: "b")
        let c = FollowUpEntry(date: day(5), note: "c")
        #expect(FollowUpHistory.displayOrder([a, b, c]).map(\.note) == ["b", "c", "a"])
    }

    /// Equal dates keep the later-added entry first, so the ordering is total and never flickers.
    @Test func displayOrder_tiesKeepTheLaterAddedFirst() {
        let first = FollowUpEntry(date: day(2), note: "first")
        let second = FollowUpEntry(date: day(2), note: "second")
        #expect(FollowUpHistory.displayOrder([first, second]).map(\.note) == ["second", "first"])
    }

    @Test func displayOrder_emptyIsEmpty() {
        #expect(FollowUpHistory.displayOrder([]).isEmpty)
    }

    // MARK: - Add / update / remove

    @Test func adding_appendsAtTheEnd_normalisedToTheDay() {
        let existing = [FollowUpEntry(date: day(1), note: "first")]
        let out = FollowUpHistory.adding(date: afternoon(4), note: "second", to: existing)
        #expect(out.map(\.note) == ["first", "second"], "append order, so the new one is pending")
        #expect(out.last?.date == day(4))
    }

    @Test func updating_keepsIdAndPosition_andNormalisesTheDay() {
        let a = FollowUpEntry(date: day(1), note: "a")
        let b = FollowUpEntry(date: day(2), note: "b")
        let out = FollowUpHistory.updating(entryID: a.id, date: afternoon(7), note: "fixed", in: [a, b])
        #expect(out.map(\.id) == [a.id, b.id], "identity and position survive a correction")
        #expect(out[0].date == day(7))
        #expect(out[0].note == "fixed")
        #expect(out[1] == b, "other entries are untouched")
    }

    @Test func updating_unknownId_changesNothing() {
        let a = FollowUpEntry(date: day(1), note: "a")
        #expect(FollowUpHistory.updating(entryID: UUID(), date: day(3), note: "x", in: [a]) == [a])
    }

    @Test func removing_dropsOnlyThatEntry() {
        let a = FollowUpEntry(date: day(1), note: "a")
        let b = FollowUpEntry(date: day(2), note: "b")
        #expect(FollowUpHistory.removing(entryID: a.id, from: [a, b]) == [b])
        #expect(FollowUpHistory.removing(entryID: UUID(), from: [a, b]) == [a, b])
    }

    // MARK: - One-time normalisation (the launch migration)

    @Test func normalized_stripsTimesFromTheTaskDateAndEveryEntry() {
        let entries = [FollowUpEntry(date: afternoon(-2), note: "old"),
                       FollowUpEntry(date: afternoon(3), note: "live")]
        let out = FollowUpHistory.normalized(followUpAt: afternoon(3), entries: entries)
        #expect(out.followUpAt == day(3))
        #expect(out.entries.map(\.date) == [day(-2), day(3)])
        #expect(out.entries.map(\.id) == entries.map(\.id), "ids and order are preserved")
        #expect(out.entries.map(\.note) == ["old", "live"])
    }

    @Test func normalized_handlesNoFollowUpAndNoEntries() {
        let out = FollowUpHistory.normalized(followUpAt: nil, entries: [])
        #expect(out.followUpAt == nil)
        #expect(out.entries.isEmpty)
    }

    @Test func needsNormalizing_onlyWhenSomethingCarriesATime() {
        #expect(FollowUpHistory.needsNormalizing(followUpAt: afternoon(1), entries: []))
        #expect(FollowUpHistory.needsNormalizing(followUpAt: nil,
                                                entries: [FollowUpEntry(date: afternoon(1), note: "x")]))
        #expect(!FollowUpHistory.needsNormalizing(followUpAt: day(1),
                                                 entries: [FollowUpEntry(date: day(0), note: "x")]))
        #expect(!FollowUpHistory.needsNormalizing(followUpAt: nil, entries: []))
    }
}
