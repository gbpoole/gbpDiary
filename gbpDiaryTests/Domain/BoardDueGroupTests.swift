import Foundation
import Testing
@testable import gbpDiary

struct BoardDueGroupTests {

    private let now = FixedDates.reference
    private var cal: Calendar { .current }

    private func inputs(due: Date?, isOpen: Bool = true, needsTriage: Bool = false,
                        isWaiting: Bool = false, isStanding: Bool = false,
                        hasHorizon: Bool = false) -> BoardDueGroup.Inputs {
        .init(isOpen: isOpen, needsTriage: needsTriage, isWaiting: isWaiting,
              isStanding: isStanding, hasHorizon: hasHorizon, dueAt: due)
    }

    private func includes(_ i: BoardDueGroup.Inputs) -> Bool {
        BoardDueGroup.includes(i, now: now, calendar: cal)
    }

    private func day(_ offset: Int) -> Date {
        cal.date(byAdding: .day, value: offset, to: now)!
    }

    @Test func dueTodayAndOverdue_areIncluded_futureIsNot() {
        #expect(includes(inputs(due: now)))            // today
        #expect(includes(inputs(due: day(-1))))        // overdue
        #expect(includes(inputs(due: day(-40))))       // long overdue
        #expect(!includes(inputs(due: day(1))))        // tomorrow
        #expect(!includes(inputs(due: nil)))           // no due date at all
    }

    /// Each disqualifying flag, one at a time, so a regression names itself.
    @Test func closedTasksAreExcluded() {
        #expect(!includes(inputs(due: day(-1), isOpen: false)))
    }

    /// Triage is a gate: the board never shows inbox work, however overdue.
    @Test func untriagedTasksAreExcluded() {
        #expect(!includes(inputs(due: day(-1), needsTriage: true)))
    }

    /// waitUntil is a deliberate "not before this date" and outranks the due date.
    @Test func waitingTasksAreExcluded() {
        #expect(!includes(inputs(due: day(-1), isWaiting: true)))
    }

    /// Standing work carries no deadline; this also guards the isOverdue/isDueToday asymmetry.
    @Test func standingTasksAreExcluded() {
        #expect(!includes(inputs(due: day(-1), isStanding: true)))
    }

    /// Placing a task graduates it into the manual section, so it must not also appear here.
    @Test func alreadyPlacedTasksAreExcluded() {
        #expect(!includes(inputs(due: day(-1), hasHorizon: true)))
    }

    @Test func membersAreSortedMostOverdueFirst() {
        struct T { let name: String; let due: Date? }
        let items = [T(name: "today", due: now),
                     T(name: "ancient", due: day(-10)),
                     T(name: "yesterday", due: day(-1)),
                     T(name: "future", due: day(3))]
        let got = BoardDueGroup.members(items, inputs: { inputs(due: $0.due) }, now: now, calendar: cal)
        #expect(got.map(\.name) == ["ancient", "yesterday", "today"])
    }

    @Test func membersIsStableForEqualDueDates() {
        struct T { let name: String; let due: Date? }
        let items = [T(name: "a", due: day(-1)), T(name: "b", due: day(-1))]
        let got = BoardDueGroup.members(items, inputs: { inputs(due: $0.due) }, now: now, calendar: cal)
        #expect(got.map(\.name) == ["a", "b"])
    }

    @Test func emptyInput_isEmpty() {
        struct T { let due: Date? }
        #expect(BoardDueGroup.members([T](), inputs: { inputs(due: $0.due) }, now: now, calendar: cal).isEmpty)
    }
}
