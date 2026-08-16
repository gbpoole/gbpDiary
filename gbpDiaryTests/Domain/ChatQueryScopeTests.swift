import Foundation
import Testing
@testable import gbpDiary

struct ChatQueryScopeTests {
    private let cal = Calendar(identifier: .gregorian)
    private var now: Date { cal.date(from: DateComponents(year: 2024, month: 6, day: 19, hour: 12))! } // Wed

    private func parse(_ q: String, projects: [String] = ["NODES - 2026B", "NODES", "Other Project"]) -> ChatQueryScope {
        ChatQueryScopeParser.parse(question: q, knownProjectNames: projects, now: now, calendar: cal)
    }

    @Test func emailsForProject_detectsKind_projectAndDropsProjectKind() {
        let s = parse("Summarise recent emails for the project \"NODES - 2026B\"")
        #expect(s.kinds == [.email])                 // "project" naming word not treated as a kind
        #expect(s.projectName == "NODES - 2026B")
        #expect(s.interval != nil)                    // "recent"
        #expect(!s.wantsOverview)
    }

    @Test func projectMatch_prefersLongestKnownName() {
        #expect(parse("emails for NODES - 2026B").projectName == "NODES - 2026B")
        #expect(parse("emails for NODES").projectName == "NODES")
    }

    @Test func kinds_detectSingularAndPlural() {
        #expect(parse("show my tasks").kinds == [.task])
        #expect(parse("recent meeting minutes").kinds == [.meeting])
        #expect(parse("what documents do I have").kinds == [.document])
    }

    @Test func interval_namedPeriods() {
        #expect(parse("emails this week").intervalLabel == "this week")
        #expect(parse("time last month").intervalLabel == "last month")
        #expect(parse("notes today").intervalLabel == "today")
        #expect(parse("hello there").interval == nil)
    }

    @Test func interval_pastN() {
        let s = parse("time spent over the past 3 weeks")
        #expect(s.intervalLabel == "the past 3 weeks")
        #expect(s.interval != nil)
    }

    @Test func overviewAndTimeTotals_flags() {
        let s = parse("Give me an overview of time spent on NODES - 2026B this week")
        #expect(s.wantsOverview)
        #expect(s.wantsTimeTotals)
        #expect(s.intervalLabel == "this week")
        #expect(s.projectName == "NODES - 2026B")
    }

    @Test func empty_whenNoSignals() {
        #expect(parse("hello there", projects: []).isEmpty)
    }

    @Test func wantsTimeTotals_detectsTotalsPhrasings() {
        #expect(parse("give me the time totals for that").wantsTimeTotals)
        #expect(parse("what are the totals").wantsTimeTotals)
        #expect(parse("how much time on NODES").wantsTimeTotals)
        #expect(!parse("summarise the work").wantsTimeTotals)
    }

    @Test func isBackReference_detectsFollowUps() {
        #expect(ChatQueryScopeParser.isBackReference("Give me the time totals for that as well"))
        #expect(ChatQueryScopeParser.isBackReference("the same again"))
        #expect(!ChatQueryScopeParser.isBackReference("Summarise emails for NODES this week"))
    }

    @Test func inheriting_fillsUnspecifiedFieldsFromPriorScope() {
        // Follow-up asks for totals but names no project/interval/kind — inherit from the prior question.
        let prior = parse("Summarise the last week of emails for NODES - 2026B")
        var followUp = parse("Give me the time totals for that as well")
        #expect(followUp.projectName == nil)
        #expect(followUp.interval == nil)
        #expect(followUp.wantsTimeTotals)
        followUp = followUp.inheriting(from: prior)
        #expect(followUp.projectName == "NODES - 2026B")
        #expect(followUp.intervalLabel == "last week")
        #expect(followUp.kinds == [.email])
        #expect(followUp.wantsTimeTotals)
    }

    @Test func inheriting_doesNotOverrideSpecifiedFields() {
        let prior = parse("emails for NODES last week")
        let current = parse("tasks for Other Project this week")
        let merged = current.inheriting(from: prior)
        #expect(merged.projectName == "Other Project")
        #expect(merged.intervalLabel == "this week")
        #expect(merged.kinds == [.task])
    }
}
