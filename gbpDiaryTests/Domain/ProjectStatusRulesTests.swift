import Foundation
import Testing
@testable import gbpDiary

struct ProjectStatusRulesTests {
    @Test func canComplete_requiresAllSubprojectsCompleted() {
        #expect(ProjectStatusRules.canComplete(subprojectsCompleted: []))              // leaf: ok
        #expect(ProjectStatusRules.canComplete(subprojectsCompleted: [true, true]))
        #expect(!ProjectStatusRules.canComplete(subprojectsCompleted: [true, false]))  // one active blocks
        #expect(!ProjectStatusRules.canComplete(subprojectsCompleted: [false]))
    }

    @Test func canReactivate_requiresParentNotCompleted() {
        #expect(ProjectStatusRules.canReactivate(parentCompleted: nil))    // no parent: ok
        #expect(ProjectStatusRules.canReactivate(parentCompleted: false))  // active parent: ok
        #expect(!ProjectStatusRules.canReactivate(parentCompleted: true))  // completed parent blocks
    }
}
