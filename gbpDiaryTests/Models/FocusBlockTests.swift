import Testing
@testable import gbpDiary

@MainActor
struct FocusBlockTests {

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
}
