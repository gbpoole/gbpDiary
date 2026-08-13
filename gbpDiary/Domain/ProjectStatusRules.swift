import Foundation

// Integrity rules for a project's Active/Completed status, preserving the invariant that a **completed
// project never contains an active descendant**. Both directions are enforced by disabling the control:
//  • a project can be marked Completed only once all its subprojects are Completed;
//  • a Completed project can be reactivated only once its parent is Active (reactivate the parent first).
// Pure/unit-testable.
enum ProjectStatusRules {
    /// A project may be marked Completed only when every direct subproject is already Completed.
    static func canComplete(subprojectsCompleted: [Bool]) -> Bool {
        subprojectsCompleted.allSatisfy { $0 }
    }

    /// A Completed project may be reactivated only when its parent isn't Completed (nil parent = ok).
    static func canReactivate(parentCompleted: Bool?) -> Bool {
        parentCompleted != true
    }
}
