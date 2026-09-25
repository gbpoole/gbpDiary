import Foundation

// Placement rules for the planning board, kept out of the view so they can be tested.
//
// Two rules matter and are easy to get wrong:
//  • a task dropped on a lane goes to the END of it (planning is append-then-reorder, never a silent
//    insert into the middle of a list you were reading);
//  • only TRIAGED tasks may be placed. Triage is a gate, not something planning does for you — a task
//    must be filed before it can be planned. (This replaced an earlier rule where placing an inbox
//    task marked it reviewed; planning no longer reviews anything.)
enum BoardPlacement {
    /// Sort order that appends after everything already in the target lane.
    static func appendOrder(existingOrders: [Int]) -> Int {
        (existingOrders.max() ?? -1) + 1
    }

    /// Whether this task may be placed on the board at all. Closed work can't be planned, and
    /// untriaged work must be filed first — the board never contains anything still in the inbox.
    static func canPlace(isOpen: Bool, needsTriage: Bool) -> Bool {
        isOpen && !needsTriage
    }
}
