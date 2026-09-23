import Foundation

// Placement rules for the planning board, kept out of the view so they can be tested.
//
// Two rules matter and are easy to get wrong:
//  • a task dropped on a column goes to the END of it (planning is append-then-reorder, never a
//    silent insert into the middle of a list you were reading);
//  • placing a task that was still in the Inbox also REVIEWS it — deciding when you'll do something
//    is the triage decision, so it should not need a second, separate "reviewed" click.
enum BoardPlacement {
    /// Sort order that appends after everything already in the target column.
    static func appendOrder(existingOrders: [Int]) -> Int {
        (existingOrders.max() ?? -1) + 1
    }

    /// Whether placing this task should also clear its triage flag.
    static func shouldReview(needsTriage: Bool) -> Bool { needsTriage }
}
