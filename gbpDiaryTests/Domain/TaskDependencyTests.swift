import Testing
import Foundation
@testable import gbpDiary

@Suite("TaskDependency")
struct TaskDependencyTests {
    @Test func wouldCreateCycle_selfAndDirect() {
        let a = UUID(), b = UUID()
        #expect(TaskDependency.wouldCreateCycle(taskID: a, newBlockerID: a, dependsOn: [:]))       // self
        // b already depends on a → making a depend on b closes a 2-cycle.
        #expect(TaskDependency.wouldCreateCycle(taskID: a, newBlockerID: b, dependsOn: [b: [a]]))
    }

    @Test func wouldCreateCycle_transitive() {
        let a = UUID(), b = UUID(), c = UUID()
        // c → b → a ; making a depend on c would loop.
        #expect(TaskDependency.wouldCreateCycle(taskID: a, newBlockerID: c, dependsOn: [c: [b], b: [a]]))
    }

    @Test func wouldCreateCycle_falseForAcyclic() {
        let a = UUID(), b = UUID(), c = UUID()
        // a depends on b, b depends on c; adding a→c is fine (still a DAG).
        #expect(!TaskDependency.wouldCreateCycle(taskID: a, newBlockerID: c, dependsOn: [a: [b], b: [c]]))
        #expect(!TaskDependency.wouldCreateCycle(taskID: a, newBlockerID: b, dependsOn: [:]))
    }
}
