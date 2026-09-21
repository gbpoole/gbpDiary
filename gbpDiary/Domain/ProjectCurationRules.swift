import Foundation

// Gate for the curation stepper, mirroring `ProjectStatusRules`. A (sub)project cannot be marked
// tasks-reviewed until every one of its open tasks that still needs triage has been reviewed — so the
// project-level "tasks reviewed" stamp can never disagree with the per-task inbox state. Pure/testable.
enum ProjectCurationRules {
    /// True when none of the project's open tasks still need triage (an empty project is trivially ok).
    static func canMarkTasksReviewed(openTaskNeedsTriage: [Bool]) -> Bool {
        !openTaskNeedsTriage.contains(true)
    }

    /// Count of open tasks still needing triage — drives the stepper's "N to review" hint.
    static func unreviewedCount(openTaskNeedsTriage: [Bool]) -> Int {
        openTaskNeedsTriage.lazy.filter { $0 }.count
    }
}
