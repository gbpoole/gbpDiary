import Testing
import Foundation
@testable import gbpDiary

@Suite("FocusBlockProjectMigration")
struct FocusBlockProjectMigrationTests {
    private func input(hasTask: Bool, project: UUID?) -> FocusBlockProjectMigration.Input {
        FocusBlockProjectMigration.Input(blockID: UUID(), hasTask: hasTask, projectID: project)
    }

    @Test func plan_emptyInput_isEmpty() {
        #expect(FocusBlockProjectMigration.plan([]).isEmpty)
    }

    @Test func plan_projectOnlyBlock_goesToTaskCreationBucket() {
        let project = UUID()
        let block = input(hasTask: false, project: project)
        let plan = FocusBlockProjectMigration.plan([block])
        #expect(plan.tasksPerProject == [project: [block.blockID]])
        #expect(plan.clearProject.isEmpty)
    }

    @Test func plan_taskBackedWithStaleProject_goesToClearBucket() {
        // A task-backed block that still carries a legacy project just has the project cleared — no new task.
        let block = input(hasTask: true, project: UUID())
        let plan = FocusBlockProjectMigration.plan([block])
        #expect(plan.clearProject == [block.blockID])
        #expect(plan.tasksPerProject.isEmpty)
    }

    @Test func plan_taskBackedNoProject_isLeftAlone() {
        #expect(FocusBlockProjectMigration.plan([input(hasTask: true, project: nil)]).isEmpty)
    }

    @Test func plan_projectlessNoTask_isLeftAlone() {
        // Evening/overtime or otherwise project-less blocks have nothing to fix.
        #expect(FocusBlockProjectMigration.plan([input(hasTask: false, project: nil)]).isEmpty)
    }

    @Test func plan_groupsMultipleProjectOnlyBlocksByProject() {
        let projectA = UUID()
        let projectB = UUID()
        let a1 = input(hasTask: false, project: projectA)
        let a2 = input(hasTask: false, project: projectA)
        let b1 = input(hasTask: false, project: projectB)
        let plan = FocusBlockProjectMigration.plan([a1, a2, b1])

        #expect(plan.tasksPerProject.count == 2)
        #expect(Set(plan.tasksPerProject[projectA] ?? []) == Set([a1.blockID, a2.blockID]))
        #expect(plan.tasksPerProject[projectB] == [b1.blockID])
        #expect(plan.clearProject.isEmpty)
    }

    @Test func plan_mixedInput_splitsAcrossBothBuckets() {
        let project = UUID()
        let projectOnly = input(hasTask: false, project: project)   // → new task
        let taskBacked = input(hasTask: true, project: UUID())      // → clear
        let cleanTask = input(hasTask: true, project: nil)          // → ignored
        let evening = input(hasTask: false, project: nil)           // → ignored
        let plan = FocusBlockProjectMigration.plan([projectOnly, taskBacked, cleanTask, evening])

        #expect(plan.tasksPerProject == [project: [projectOnly.blockID]])
        #expect(plan.clearProject == [taskBacked.blockID])
    }
}
