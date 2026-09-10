import Foundation

// Time can only be assigned to tasks, not projects. `FocusBlock.project` is now a legacy field: the UI no
// longer creates project-backed blocks, and this one-time migration converts any that exist into task-backed
// blocks (one auto-created task per project — see WorkspaceView.migrateFocusBlockProjectsOnce).
//
// `plan` is the pure decision over a lightweight view of every focus block. Any block still carrying a
// legacy `project` needs fixing, in one of two ways:
//   • project-only (no task)  → create one task per project and back the block with it (`tasksPerProject`).
//   • task-backed with a stale project (e.g. an Obsidian-imported block) → just null the project; the task
//     already owns it (`clearProject`).
// Blocks with no project are left alone. Idempotent by design — a fixed block no longer carries a project,
// so a re-run plans nothing.
nonisolated enum FocusBlockProjectMigration {
    struct Input: Equatable {
        let blockID: UUID
        let hasTask: Bool
        let projectID: UUID?

        init(blockID: UUID, hasTask: Bool, projectID: UUID?) {
            self.blockID = blockID
            self.hasTask = hasTask
            self.projectID = projectID
        }
    }

    struct Plan: Equatable {
        var tasksPerProject: [UUID: [UUID]]   // project id → project-only block ids to back with one new task
        var clearProject: [UUID]              // task-backed block ids whose stale legacy project is just cleared
        var isEmpty: Bool { tasksPerProject.isEmpty && clearProject.isEmpty }
    }

    static func plan(_ inputs: [Input]) -> Plan {
        var tasksPerProject: [UUID: [UUID]] = [:]
        var clearProject: [UUID] = []
        for input in inputs {
            guard let projectID = input.projectID else { continue }  // no legacy project → nothing to fix
            if input.hasTask {
                clearProject.append(input.blockID)
            } else {
                tasksPerProject[projectID, default: []].append(input.blockID)
            }
        }
        return Plan(tasksPerProject: tasksPerProject, clearProject: clearProject)
    }
}
