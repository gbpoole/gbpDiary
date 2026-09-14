import Testing
import Foundation
@testable import gbpDiary

@Suite("TaskSourceMigration")
struct TaskSourceMigrationTests {
    private func input(hasSource: Bool, hasOriginEmail: Bool) -> TaskSourceMigration.Input {
        TaskSourceMigration.Input(taskID: UUID(), hasSource: hasSource, hasOriginEmail: hasOriginEmail)
    }

    @Test func plansEmailTasksWithoutASource() {
        let needs = input(hasSource: false, hasOriginEmail: true)
        #expect(TaskSourceMigration.plan([needs]) == [needs.taskID])
    }

    @Test func skipsTasksThatAlreadyHaveASource() {
        #expect(TaskSourceMigration.plan([input(hasSource: true, hasOriginEmail: true)]).isEmpty)
    }

    @Test func skipsTasksWithNoOriginEmail() {
        #expect(TaskSourceMigration.plan([input(hasSource: false, hasOriginEmail: false)]).isEmpty)
    }

    @Test func emptyInput_isEmpty() {
        #expect(TaskSourceMigration.plan([]).isEmpty)
    }
}
