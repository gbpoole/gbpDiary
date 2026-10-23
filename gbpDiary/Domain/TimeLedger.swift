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

// A project as the ledger identifies it: a STABLE key (the `Project.id` UUID string) plus a display name.
// Keying on identity rather than name is what stops two same-named subprojects collapsing into one row, and
// keeps a report's sections stable across a rename.
nonisolated struct LedgerProject: Hashable, Sendable {
    let key: String
    let name: String

    init(key: String, name: String) {
        self.key = key
        self.name = name
    }

    /// A project known only by name (the unattributed sentinel, and name-shaped test input).
    init(name: String) { self.init(key: name, name: name) }
}

nonisolated struct LedgerBlock: Equatable, Sendable {
    let id: UUID
    let date: Date
    let capacityHours: Double
    let project: LedgerProject?
    let isOvertime: Bool
}

// Where an activity came from. The ledger doesn't interpret this — it carries it so a consumer (the
// Timesheet) can turn the SAME filtered, de-duplicated, weekend-folded activity set the hours come from
// into narrative rows, instead of re-walking the models under re-implemented rules and drifting.
nonisolated struct LedgerOrigin: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case taskEntry          // a TaskTimeEntry against a task
        case legacyTask         // a completed task's legacy `duration`
        case meeting            // a Minutes
        case conversationEntry  // a TaskTimeEntry owned by an EmailConversation
    }
    let kind: Kind
    let modelID: UUID        // the TaskTimeEntry / Task / Minutes id
    let ownerID: UUID?       // the Task (for a task entry) or EmailConversation that owns it
}

nonisolated struct LedgerActivity: Equatable, Sendable {
    let sourceKey: String            // stable per underlying record (dedupe)
    let date: Date
    let hours: Double
    let projects: [LedgerProject]    // its own project(s); empty = unattributed
    let blockID: UUID?               // the focus block it falls inside, or nil (standalone)
    let isOvertime: Bool             // evening in-block or weekend work
    let origin: LedgerOrigin?        // provenance, for consumers that need to name the work

    init(sourceKey: String, date: Date, hours: Double, projects: [LedgerProject],
         blockID: UUID?, isOvertime: Bool, origin: LedgerOrigin? = nil) {
        self.sourceKey = sourceKey
        self.date = date
        self.hours = hours
        self.projects = projects
        self.blockID = blockID
        self.isOvertime = isOvertime
        self.origin = origin
    }
}

nonisolated struct LedgerProjectHours: Equatable, Sendable {
    let key: String              // TimeLedger.noProject for unattributed
    let name: String
    let hours: Double
    let distinctWeeks: Int       // distinct calendar weeks with time on this project

    init(key: String, name: String, hours: Double, distinctWeeks: Int) {
        self.key = key
        self.name = name
        self.hours = hours
        self.distinctWeeks = distinctWeeks
    }

    /// Name-keyed, for a project known only by name (the unattributed bucket, name-shaped test input).
    init(name: String, hours: Double, distinctWeeks: Int) {
        self.init(key: name, name: name, hours: hours, distinctWeeks: distinctWeeks)
    }
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
    /// The bucket unattributed time accumulates into (key == name, so it is never confused with a real id).
    static let unattributed = LedgerProject(name: noProject)

    /// The inputs that actually count: interval-filtered, and de-duplicated by `sourceKey`. `compute` uses
    /// this, and so must any consumer deriving a narrative from the same hours — otherwise the two drift.
    static func filtered(blocks: [LedgerBlock], activities: [LedgerActivity],
                         interval: Range<Date>? = nil) -> (blocks: [LedgerBlock], activities: [LedgerActivity]) {
        var seen = Set<String>()
        return (interval.map { iv in blocks.filter { iv.contains($0.date) } } ?? blocks,
                (interval.map { iv in activities.filter { iv.contains($0.date) } } ?? activities)
                    .filter { seen.insert($0.sourceKey).inserted })
    }

    static func compute(blocks: [LedgerBlock], activities: [LedgerActivity],
                        interval: Range<Date>? = nil, calendar: Calendar = .current) -> LedgerResult {
        let (blocks, activities) = filtered(blocks: blocks, activities: activities, interval: interval)

        // Hours logged inside each block (drives net-remaining).
        var inBlockLogged: [UUID: Double] = [:]
        for a in activities where a.blockID != nil { inBlockLogged[a.blockID!, default: 0] += a.hours }

        // Per-project accumulation, keyed on project IDENTITY (name is carried for display only).
        var byProject: [String: Double] = [:]
        var names: [String: String] = [:]
        var order: [String] = []
        var weeksByProject: [String: Set<String>] = [:]
        func add(_ project: LedgerProject, _ hours: Double, on date: Date) {
            guard hours > 0 else { return }
            if byProject[project.key] == nil { order.append(project.key) }
            names[project.key] = project.name
            byProject[project.key, default: 0] += hours
            let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            weeksByProject[project.key, default: []].insert("\(c.yearForWeekOfYear ?? 0)-\(c.weekOfYear ?? 0)")
        }

        var blockNet: [UUID: Double] = [:]
        for b in blocks {
            let net = max(0, b.capacityHours - (inBlockLogged[b.id] ?? 0))
            blockNet[b.id] = net
            if !b.isOvertime { add(b.project ?? unattributed, net, on: b.date) }  // overtime capacity isn't counted
        }
        for a in activities {
            let projects = a.projects.isEmpty ? [unattributed] : a.projects
            for p in projects { add(p, a.hours, on: a.date) }
        }

        // Totals mirror the diary exactly: standard = non-overtime block capacity + standalone weekday work.
        let standardCapacity = blocks.filter { !$0.isOvertime }.reduce(0.0) { $0 + $1.capacityHours }
        let standaloneWeekday = activities.filter { $0.blockID == nil && !$0.isOvertime }.reduce(0.0) { $0 + $1.hours }
        let overtime = activities.filter(\.isOvertime).reduce(0.0) { $0 + $1.hours }

        let perProject = order
            .map { LedgerProjectHours(key: $0, name: names[$0] ?? $0, hours: byProject[$0] ?? 0,
                                      distinctWeeks: weeksByProject[$0]?.count ?? 0) }
            .sorted { $0.hours != $1.hours ? $0.hours > $1.hours : $0.name < $1.name }
        return LedgerResult(perProject: perProject, standardTotal: standardCapacity + standaloneWeekday,
                            overtime: overtime, blockNet: blockNet)
    }
}
