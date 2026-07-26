import Testing
import Foundation
@testable import gbpDiary

@MainActor
struct FocusBlockTests {

    // MARK: - netHours

    @Test func focusBlock_netHours_subtractsActivities() {
        let block = FocusBlock(duration: Duration(value: 2, unit: .h))
        let e1 = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 0.5, unit: .h))
        let e2 = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 0.5, unit: .h))
        block.activities = [e1, e2]
        #expect(block.netHours == 1.0)
    }

    @Test func focusBlock_netHours_clampsToZero() {
        let block = FocusBlock(duration: Duration(value: 1, unit: .h))
        let e = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 2, unit: .h))
        block.activities = [e]
        #expect(block.netHours == 0.0)
    }

    // MARK: - displayLabel

    @Test func displayLabel_prefersTaskSummary() {
        // Both task and project set — task must win
        let block = FocusBlock(duration: Duration(value: 1, unit: .h))
        block.task = Task(summary: "Write report")
        block.project = Project(name: "ShouldBeIgnored")
        #expect(block.displayLabel == "Write report")
    }

    @Test func displayLabel_usesProjectNameWhenNoTask() {
        let block = FocusBlock(duration: Duration(value: 1, unit: .h))
        block.project = Project(name: "Alpha")
        #expect(block.displayLabel == "Alpha")
    }

    @Test func displayLabel_fallsBackToSlotNameWhenNeitherSet() {
        let block = FocusBlock(duration: Duration(value: 1, unit: .h), slot: .morning)
        #expect(block.displayLabel == "Morning")
    }

    // MARK: - slot

    @Test func slot_defaultsToAllDay() {
        let block = FocusBlock(duration: Duration(value: 1, unit: .d))
        #expect(block.slot == .allDay)
    }

    @Test func slot_initWithMorning_roundTrips() {
        let block = FocusBlock(duration: Duration(value: 0.5, unit: .d), slot: .morning)
        #expect(block.slot == .morning)
    }

    @Test func slot_initWithAfternoon_roundTrips() {
        let block = FocusBlock(duration: Duration(value: 0.5, unit: .d), slot: .afternoon)
        #expect(block.slot == .afternoon)
    }

    @Test func slot_canBeMutatedAfterInit() {
        let block = FocusBlock(duration: Duration(value: 1, unit: .d))
        block.slot = .morning
        #expect(block.slot == .morning)
        block.slot = .allDay
        #expect(block.slot == .allDay)
    }

    // MARK: - FocusBlockAssignment.containingBlock

    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2024; comps.month = 1; comps.day = 15
        comps.hour = hour; comps.minute = minute
        return utc.date(from: comps)!
    }
    private func makeBlock(_ slot: DaySlot, start: Date? = nil) -> FocusBlock {
        let b = FocusBlock(duration: slot.defaultDuration, slot: slot)
        b.startTime = start
        return b
    }

    @Test func containingBlock_matchesSlotByTime() {
        let m = makeBlock(.morning); let a = makeBlock(.afternoon)
        #expect(FocusBlockAssignment.containingBlock(for: time(9), blocks: [m, a], calendar: utc)?.id == m.id)
        #expect(FocusBlockAssignment.containingBlock(for: time(15), blocks: [m, a], calendar: utc)?.id == a.id)
    }

    @Test func containingBlock_fallsBackToAllDay() {
        let allDay = makeBlock(.allDay)
        #expect(FocusBlockAssignment.containingBlock(for: time(9), blocks: [allDay], calendar: utc)?.id == allDay.id)
        #expect(FocusBlockAssignment.containingBlock(for: time(20), blocks: [allDay], calendar: utc)?.id == allDay.id)
    }

    @Test func containingBlock_eveningWinsAfterItsStart() {
        let allDay = makeBlock(.allDay); let evening = makeBlock(.evening, start: time(18))
        let blocks = [allDay, evening]
        #expect(FocusBlockAssignment.containingBlock(for: time(20), blocks: blocks, calendar: utc)?.id == evening.id)
        #expect(FocusBlockAssignment.containingBlock(for: time(10), blocks: blocks, calendar: utc)?.id == allDay.id)
        #expect(FocusBlockAssignment.containingBlock(for: time(17, 59), blocks: blocks, calendar: utc)?.id == allDay.id)
    }

    @Test func containingBlock_nilWhenOutOfRange() {
        let m = makeBlock(.morning)
        // 15:00 is afternoon, but there is no afternoon or all-day block → standalone.
        #expect(FocusBlockAssignment.containingBlock(for: time(15), blocks: [m], calendar: utc) == nil)
    }
}
