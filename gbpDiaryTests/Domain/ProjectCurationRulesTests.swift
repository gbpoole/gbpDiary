import Foundation
import Testing
@testable import gbpDiary

struct ProjectCurationRulesTests {
    @Test func canMarkTasksReviewed_requiresNoUntriagedOpenTask() {
        #expect(ProjectCurationRules.canMarkTasksReviewed(openTaskNeedsTriage: []))            // empty: ok
        #expect(ProjectCurationRules.canMarkTasksReviewed(openTaskNeedsTriage: [false, false]))
        #expect(!ProjectCurationRules.canMarkTasksReviewed(openTaskNeedsTriage: [false, true]))
        #expect(!ProjectCurationRules.canMarkTasksReviewed(openTaskNeedsTriage: [true]))
    }

    @Test func unreviewedCount_countsUntriaged() {
        #expect(ProjectCurationRules.unreviewedCount(openTaskNeedsTriage: []) == 0)
        #expect(ProjectCurationRules.unreviewedCount(openTaskNeedsTriage: [true, false, true]) == 2)
        #expect(ProjectCurationRules.unreviewedCount(openTaskNeedsTriage: [false, false]) == 0)
    }
}
