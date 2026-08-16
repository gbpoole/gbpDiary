import Foundation
import Testing
@testable import gbpDiary

struct ChatQuerySpecMappingTests {
    private let cal = Calendar(identifier: .gregorian)
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 12))! }
    private let known = ["NODES - 2026B", "Other Project"]

    // MARK: ChatDatePeriod

    @Test func period_windows() {
        #expect(ChatDatePeriod.none.window(now: now, calendar: cal) == nil)
        #expect(ChatDatePeriod.lastWeek.window(now: now, calendar: cal)?.label == "last week")
        #expect(ChatDatePeriod.lastMonth.window(now: now, calendar: cal)?.label == "last month")
        #expect(ChatDatePeriod.today.window(now: now, calendar: cal)?.label == "today")
        // last month (May) contains 20 May, not 10 June.
        let may = ChatDatePeriod.lastMonth.window(now: now, calendar: cal)!.range
        #expect(may.contains(cal.date(from: DateComponents(year: 2026, month: 5, day: 20))!))
        #expect(!may.contains(cal.date(from: DateComponents(year: 2026, month: 6, day: 10))!))
    }

    // MARK: resolveKinds / resolveProject

    @Test func resolveKinds_whitelistsAndDropsUnknown() {
        #expect(ChatQuerySpecMapping.resolveKinds(["email", "meeting"]) == [.email, .meeting])
        #expect(ChatQuerySpecMapping.resolveKinds(["EMAIL"]) == [.email])
        #expect(ChatQuerySpecMapping.resolveKinds(["banana", ""]).isEmpty)
        #expect(ChatQuerySpecMapping.resolveKinds(["diary"]) == [.day])
    }

    @Test func resolveProject_validatesAgainstKnownNames() {
        #expect(ChatQuerySpecMapping.resolveProject("NODES - 2026B", knownProjectNames: known) == "NODES - 2026B")
        #expect(ChatQuerySpecMapping.resolveProject("nodes - 2026b", knownProjectNames: known) == "NODES - 2026B")
        #expect(ChatQuerySpecMapping.resolveProject("NODES", knownProjectNames: known) == "NODES - 2026B") // containment
        #expect(ChatQuerySpecMapping.resolveProject("Totally Made Up", knownProjectNames: known) == nil)
        #expect(ChatQuerySpecMapping.resolveProject("", knownProjectNames: known) == nil)
        #expect(ChatQuerySpecMapping.resolveProject("none", knownProjectNames: known) == nil)
    }

    // MARK: merge (LM refines, heuristic backstops — never a regression)

    @Test func merge_lmKindsOverrideEmptyHeuristic() {
        let heuristic = ChatQueryScope()
        let merged = ChatQuerySpecMapping.merge(lmKinds: ["email"], lmProjectName: "", lmPeriod: .none,
            lmWantsTotals: false, lmWantsOverview: false, heuristic: heuristic,
            knownProjectNames: known, now: now, calendar: cal)
        #expect(merged.kinds == [.email])
    }

    @Test func merge_lmProjectResolvedAndDropsProjectKind() {
        var heuristic = ChatQueryScope(); heuristic.kinds = [.project]
        let merged = ChatQuerySpecMapping.merge(lmKinds: [], lmProjectName: "NODES", lmPeriod: .none,
            lmWantsTotals: false, lmWantsOverview: false, heuristic: heuristic,
            knownProjectNames: known, now: now, calendar: cal)
        #expect(merged.projectName == "NODES - 2026B")
        #expect(!merged.kinds.contains(.project))
    }

    @Test func merge_lmPeriodSetsInterval_elseKeepsHeuristic() {
        var heuristic = ChatQueryScope()
        heuristic.interval = now..<now; heuristic.intervalLabel = "the past 3 weeks"  // e.g. a pastN the enum can't express
        // LM says none → keep the heuristic's pastN window.
        let kept = ChatQuerySpecMapping.merge(lmKinds: [], lmProjectName: "", lmPeriod: .none,
            lmWantsTotals: false, lmWantsOverview: false, heuristic: heuristic,
            knownProjectNames: known, now: now, calendar: cal)
        #expect(kept.intervalLabel == "the past 3 weeks")
        // LM says lastWeek → overrides.
        let overridden = ChatQuerySpecMapping.merge(lmKinds: [], lmProjectName: "", lmPeriod: .lastWeek,
            lmWantsTotals: false, lmWantsOverview: false, heuristic: heuristic,
            knownProjectNames: known, now: now, calendar: cal)
        #expect(overridden.intervalLabel == "last week")
    }

    @Test func merge_flagsAreUnioned_neverDropHeuristicTrue() {
        var heuristic = ChatQueryScope(); heuristic.wantsTimeTotals = true
        // LM false must not clear a heuristic-detected totals intent.
        let merged = ChatQuerySpecMapping.merge(lmKinds: [], lmProjectName: "", lmPeriod: .none,
            lmWantsTotals: false, lmWantsOverview: true, heuristic: heuristic,
            knownProjectNames: known, now: now, calendar: cal)
        #expect(merged.wantsTimeTotals)     // kept from heuristic
        #expect(merged.wantsOverview)       // added by LM
    }

    @Test func merge_emptyLM_returnsHeuristicUnchanged() {
        var heuristic = ChatQueryScope()
        heuristic.kinds = [.email]; heuristic.projectName = "NODES - 2026B"
        let merged = ChatQuerySpecMapping.merge(lmKinds: [], lmProjectName: "", lmPeriod: .none,
            lmWantsTotals: false, lmWantsOverview: false, heuristic: heuristic,
            knownProjectNames: known, now: now, calendar: cal)
        #expect(merged.kinds == [.email])
        #expect(merged.projectName == "NODES - 2026B")
    }
}
