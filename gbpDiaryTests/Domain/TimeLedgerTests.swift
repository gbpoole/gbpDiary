import Foundation
import Testing
@testable import gbpDiary

struct TimeLedgerTests {
    private let cal = Calendar(identifier: .gregorian)
    // 2024-01-03 Wed, 01-05 Fri, 01-10 next-Wed.
    private func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2024, month: 1, day: d, hour: 10))! }

    private func block(_ id: UUID, _ date: Date, _ cap: Double, _ project: String?, overtime: Bool = false) -> LedgerBlock {
        LedgerBlock(id: id, date: date, capacityHours: cap, projectName: project, isOvertime: overtime)
    }
    private func act(_ key: String, _ date: Date, _ hours: Double, _ projects: [String], block: UUID? = nil, overtime: Bool = false) -> LedgerActivity {
        LedgerActivity(sourceKey: key, date: date, hours: hours, projectNames: projects, blockID: block, isOvertime: overtime)
    }
    private func hours(_ r: LedgerResult, _ name: String) -> Double? { r.perProject.first { $0.name == name }?.hours }

    // The reported bug: a 3h NODES block with a 1h ADACS meeting inside ⇒ NODES 2h, ADACS 1h, total 3h.
    @Test func inBlockActivity_attributedToOwnProject_reducesBlockNet() {
        let b = UUID()
        let r = TimeLedger.compute(
            blocks: [block(b, day(3), 3, "NODES")],
            activities: [act("m1", day(3), 1, ["ADACS"], block: b)],
            calendar: cal)
        #expect(hours(r, "NODES") == 2)
        #expect(hours(r, "ADACS") == 1)
        #expect(r.blockNet[b] == 2)
        #expect(r.standardTotal == 3)
        #expect(r.grandTotal == 3)
    }

    @Test func standaloneActivity_countsToProjectAndStandardTotal() {
        let r = TimeLedger.compute(blocks: [], activities: [act("e1", day(3), 1, ["Alpha"])], calendar: cal)
        #expect(hours(r, "Alpha") == 1)
        #expect(r.standardTotal == 1)
        #expect(r.blockNet.isEmpty)
    }

    @Test func overLoggedBlock_netZero_perProjectIsActual() {
        let b = UUID()
        let r = TimeLedger.compute(
            blocks: [block(b, day(3), 3, "NODES")],
            activities: [act("x", day(3), 4, ["ADACS"], block: b)],
            calendar: cal)
        #expect(r.blockNet[b] == 0)
        #expect(hours(r, "NODES") == nil)      // net 0 → not attributed
        #expect(hours(r, "ADACS") == 4)         // actual logged
        #expect(r.standardTotal == 3)           // diary total stays capacity-based
        #expect(r.perProjectTotal == 4)         // per-project reflects actual (exceeds total when over-logged)
    }

    @Test func overtime_eveningInBlockAndWeekend_notInStandardTotal() {
        let evening = UUID()
        let r = TimeLedger.compute(
            blocks: [block(evening, day(3), 0, "NODES", overtime: true)],
            activities: [
                act("ev", day(3), 1.5, ["NODES"], block: evening, overtime: true),   // evening in-block
                act("wk", day(5), 2, ["ADACS"], overtime: true),                      // weekend (folded to Fri)
            ], calendar: cal)
        #expect(r.overtime == 3.5)
        #expect(r.standardTotal == 0)           // overtime work isn't in standard total
        #expect(hours(r, "NODES") == 1.5)
        #expect(hours(r, "ADACS") == 2)
    }

    @Test func distinctWeeks_perProject() {
        let r = TimeLedger.compute(blocks: [], activities: [
            act("a", day(3), 1, ["Alpha"]),        // week 1
            act("b", day(5), 1, ["Alpha"]),        // same week
            act("c", day(10), 1, ["Alpha"]),       // next week
        ], calendar: cal)
        #expect(r.perProject.first { $0.name == "Alpha" }?.distinctWeeks == 2)
        #expect(hours(r, "Alpha") == 3)
    }

    @Test func intervalFilter_dropsOutOfWindow() {
        let r = TimeLedger.compute(blocks: [], activities: [
            act("in", day(3), 1, ["Alpha"]),
            act("out", day(10), 5, ["Alpha"]),
        ], interval: day(1)..<day(6), calendar: cal)
        #expect(hours(r, "Alpha") == 1)
    }

    @Test func multiProjectActivity_attributesToEach_totalCountsOnce() {
        let r = TimeLedger.compute(blocks: [], activities: [act("m", day(3), 1, ["Alpha", "Beta"])], calendar: cal)
        #expect(hours(r, "Alpha") == 1)
        #expect(hours(r, "Beta") == 1)
        #expect(r.standardTotal == 1)           // the day still only spent 1h
        #expect(r.perProjectTotal == 2)         // but attributed to each project
    }

    @Test func dedupeBySourceKey() {
        let r = TimeLedger.compute(blocks: [], activities: [
            act("dup", day(3), 2, ["Alpha"]),
            act("dup", day(3), 2, ["Alpha"]),
        ], calendar: cal)
        #expect(r.standardTotal == 2)
        #expect(hours(r, "Alpha") == 2)
    }

    // standardTotal reproduces ActivitySection.totalHours: standard block capacity + standalone weekday work.
    @Test func standardTotal_mirrorsDiaryFormula() {
        let b = UUID()
        let r = TimeLedger.compute(
            blocks: [block(b, day(3), 3, "NODES")],
            activities: [
                act("inblock", day(3), 1, ["NODES"], block: b),   // subsumed by capacity
                act("standalone", day(3), 0.5, ["Alpha"]),        // adds on top
                act("weekend", day(5), 1, ["Beta"], overtime: true),
            ], calendar: cal)
        #expect(r.standardTotal == 3.5)         // capacity 3 + standalone 0.5
        #expect(r.overtime == 1)
        #expect(r.grandTotal == 4.5)
    }
}
