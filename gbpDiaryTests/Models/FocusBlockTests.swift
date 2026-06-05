import Testing
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

    @Test func displayLabel_fallsBackToDefaultWhenNeitherSet() {
        let block = FocusBlock(duration: Duration(value: 1, unit: .h))
        #expect(block.displayLabel == "Focus block")
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
}
