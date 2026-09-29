import Foundation

// Which tasks the Reviewed Tasks table hides. Three kinds of task are deliberately kept out of the
// main list, each revealed by its own control, and they are gathered here so the rules are stated
// once and can be tested:
//
//  • **Untriaged** open tasks live in the Inbox (the Triage view) until reviewed — a closed task is
//    never hidden for this reason, since there is no point triaging something already done. The
//    "Needs triage" flag filter reveals them, which is how a freshly captured task reaches the
//    planning board: placing it there marks it reviewed, so planning doubles as triage.
//  • **Standing** tasks are perpetual and never complete, so they would otherwise sit in the table
//    forever; the "Standing" flag filter reveals them.
enum TaskTableVisibility {
    static func isHidden(isOpen: Bool,
                         needsTriage: Bool,
                         isStanding: Bool,
                         showStanding: Bool,
                         showNeedsTriage: Bool) -> Bool {
        if isOpen && needsTriage && !showNeedsTriage { return true }
        if isStanding && !showStanding { return true }
        return false
    }
}
