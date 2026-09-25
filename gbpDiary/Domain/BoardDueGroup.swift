import Foundation

// The Today lane's **derived** "Due & overdue" group.
//
// Nothing here is written: membership is recomputed from dates every render, so `planHorizon` stays
// purely manual and a task leaves the group by having its date changed, being planned, or being
// completed. That keeps "placement is manual and never expires" literally true.
//
// A task qualifies only when every one of these holds:
//  • **open** — finished work isn't due;
//  • **triaged** — triage is a gate; the board never shows anything still in the inbox (overdue
//    captures surface in the Triage list's own due group instead);
//  • **not waiting** — `waitUntil` is a deliberate "not before this date" and is honoured;
//  • **not standing** — perpetual work carries no deadline (and holds no `dueAt` at all);
//  • **unplaced** — placing it graduates it into the lane's manual section, so it never appears twice;
//  • **due today or earlier**.
enum BoardDueGroup {

    struct Inputs {
        var isOpen: Bool
        var needsTriage: Bool
        var isWaiting: Bool
        var isStanding: Bool
        var hasHorizon: Bool
        var dueAt: Date?
    }

    /// Whether one task belongs in the derived group.
    static func includes(_ t: Inputs, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard t.isOpen, !t.needsTriage, !t.isWaiting, !t.isStanding, !t.hasHorizon else { return false }
        guard let due = t.dueAt else { return false }
        return due < calendar.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)
    }

    /// The group's members, most overdue first. Ties keep input order so the result is stable.
    static func members<Item>(_ items: [Item],
                              inputs: (Item) -> Inputs,
                              now: Date = Date(),
                              calendar: Calendar = .current) -> [Item] {
        items.enumerated()
            .filter { includes(inputs($0.element), now: now, calendar: calendar) }
            .sorted { lhs, rhs in
                let l = inputs(lhs.element).dueAt ?? .distantFuture
                let r = inputs(rhs.element).dueAt ?? .distantFuture
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
