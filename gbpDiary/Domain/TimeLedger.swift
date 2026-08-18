import Foundation

// The single source of truth for "time spent" across the app (diary, Timesheet, Chat). Given the day's
// (or a range's) focus blocks + logged activities, it produces per-project hours, the day Total and
// Overtime, and each block's net-remaining — all from ONE model, so the three consumers can never disagree.
//
// The model:
//   • Every logged ACTIVITY (task time entry, meeting, sent-email time, completed-task duration) counts
//     ONCE, against its OWN project.
//   • Every standard (non-overtime) BLOCK contributes its NET = max(0, capacity − Σ in-block activity
//     hours) to the block's project — its planned-but-unlogged time. Overtime (evening) blocks contribute
//     no capacity; only their in-block activities count (as overtime), matching the diary.
//   • So per-project = block-nets + activities, and it sums to Total + Overtime except when a block is
//     over-logged (activities > capacity), where per-project reflects the more accurate actual hours.
// Dates are expected pre-folded (weekend → Friday) by the projector; `isOvertime` marks evening/weekend.

nonisolated struct LedgerBlock: Equatable, Sendable {
    let id: UUID
    let date: Date
    let capacityHours: Double
    let projectName: String?
    let isOvertime: Bool
}

nonisolated struct LedgerActivity: Equatable, Sendable {
    let sourceKey: String        // stable per underlying record (dedupe)
    let date: Date
    let hours: Double
    let projectNames: [String]   // its own project(s); empty = unattributed
    let blockID: UUID?           // the focus block it falls inside, or nil (standalone)
    let isOvertime: Bool         // evening in-block or weekend work
}

nonisolated struct LedgerProjectHours: Equatable, Sendable {
    let name: String             // TimeLedger.noProject for unattributed
    let hours: Double
    let distinctWeeks: Int       // distinct calendar weeks with time on this project
}

nonisolated struct LedgerResult: Equatable, Sendable {
    let perProject: [LedgerProjectHours]   // descending by hours
    let standardTotal: Double               // the diary's "Total" (standard-block capacity + standalone weekday work)
    let overtime: Double                    // the diary's "Overtime" (evening in-block + weekend)
    let blockNet: [UUID: Double]            // per-block net remaining (for FocusBlockRow)

    var grandTotal: Double { standardTotal + overtime }
    var perProjectTotal: Double { perProject.reduce(0) { $0 + $1.hours } }
}

nonisolated enum TimeLedger {
    static let noProject = "(no project)"

    static func compute(blocks: [LedgerBlock], activities: [LedgerActivity],
                        interval: Range<Date>? = nil, calendar: Calendar = .current) -> LedgerResult {
        let blocks = interval.map { iv in blocks.filter { iv.contains($0.date) } } ?? blocks
        var seen = Set<String>()
        let activities = (interval.map { iv in activities.filter { iv.contains($0.date) } } ?? activities)
            .filter { seen.insert($0.sourceKey).inserted }

        // Hours logged inside each block (drives net-remaining).
        var inBlockLogged: [UUID: Double] = [:]
        for a in activities where a.blockID != nil { inBlockLogged[a.blockID!, default: 0] += a.hours }

        // Per-project accumulation.
        var byProject: [String: Double] = [:]
        var order: [String] = []
        var weeksByProject: [String: Set<String>] = [:]
        func add(_ name: String, _ hours: Double, on date: Date) {
            guard hours > 0 else { return }
            if byProject[name] == nil { order.append(name) }
            byProject[name, default: 0] += hours
            let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            weeksByProject[name, default: []].insert("\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)")
        }

        var blockNet: [UUID: Double] = [:]
        for b in blocks {
            let net = max(0, b.capacityHours - (inBlockLogged[b.id] ?? 0))
            blockNet[b.id] = net
            if !b.isOvertime { add(b.projectName ?? noProject, net, on: b.date) }  // overtime capacity isn't counted
        }
        for a in activities {
            let names = a.projectNames.isEmpty ? [noProject] : a.projectNames
            for n in names { add(n, a.hours, on: a.date) }
        }

        // Totals mirror the diary exactly: standard = non-overtime block capacity + standalone weekday work.
        let standardCapacity = blocks.filter { !$0.isOvertime }.reduce(0.0) { $0 + $1.capacityHours }
        let standaloneWeekday = activities.filter { $0.blockID == nil && !$0.isOvertime }.reduce(0.0) { $0 + $1.hours }
        let overtime = activities.filter(\.isOvertime).reduce(0.0) { $0 + $1.hours }

        let perProject = order
            .map { LedgerProjectHours(name: $0, hours: byProject[$0] ?? 0, distinctWeeks: weeksByProject[$0]?.count ?? 0) }
            .sorted { $0.hours != $1.hours ? $0.hours > $1.hours : $0.name < $1.name }
        return LedgerResult(perProject: perProject, standardTotal: standardCapacity + standaloneWeekday,
                            overtime: overtime, blockNet: blockNet)
    }
}
