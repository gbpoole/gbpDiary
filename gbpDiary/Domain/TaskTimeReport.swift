import Foundation

// Pure "time spent on a task" total, shared by the Tasks-table Time column and the task detail Time Log.
// A task's time = its logged time entries + the dynamic NET of the focus blocks it backs (net = block
// capacity − time logged to other activities within it, from the canonical TimeLedger.blockNet). The legacy
// `duration` is a fallback used only when the task has no entries AND no focus blocks. Consistent with the
// ledger's day/project totals: an in-block entry reduces its block's net, and adding it back via the entry
// sum nets to capacity — so there's no double count.
nonisolated enum TaskTimeReport {
    static func totalHours(entryHours: Double, hasEntries: Bool, legacyHours: Double?, blockNets: [Double]) -> Double {
        if hasEntries || !blockNets.isEmpty {
            return entryHours + blockNets.reduce(0, +)
        }
        return legacyHours ?? 0
    }
}
