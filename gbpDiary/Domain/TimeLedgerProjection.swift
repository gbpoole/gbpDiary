import Foundation

// Projects the SwiftData models into `TimeLedger` inputs, reusing the existing membership/fold helpers so
// nothing is re-derived: `FocusBlockAssignment.containingBlock` (which block an item's time falls in) and
// `WeekendPolicy`/`ChatWeekendFold` (weekend work → the preceding Friday, marked overtime). This is the one
// place @Model → ledger, used by Chat/Timesheet (which have `[Task]`) and the diary (which has the day's
// flattened `[TaskTimeEntry]` + `[EmailMessage]` + completed tasks).
@MainActor
enum TimeLedgerProjection {

    // MARK: Chat / Timesheet (task-shaped input)

    static func project(focusBlocks: [FocusBlock], tasks: [Task], conversations: [EmailConversation],
                        meetings: [Minutes],
                        calendar: Calendar = .current) -> (blocks: [LedgerBlock], activities: [LedgerActivity]) {
        let ctx = Context(focusBlocks: focusBlocks, calendar: calendar)
        var activities: [LedgerActivity] = []
        for task in tasks {
            let names = [task.project?.name].compactMap { $0 }
            if task.timeEntries.isEmpty {
                if let c = task.completedAt, let d = task.duration {
                    activities.append(ctx.legacyTask(id: task.id.uuidString, completedAt: c, hours: d.hoursNormalized, projects: names))
                }
            } else {
                for e in task.timeEntries where e.email == nil && e.conversation == nil {
                    activities.append(ctx.entry(id: e.id.uuidString, date: e.date, hours: e.duration.hoursNormalized, projects: names))
                }
            }
        }
        activities += conversationActivities(conversations, ctx)
        activities += meetingActivities(meetings, ctx)
        return (ctx.blocks, activities)
    }

    static func ledger(focusBlocks: [FocusBlock], tasks: [Task], conversations: [EmailConversation],
                       meetings: [Minutes],
                       interval: Range<Date>? = nil, calendar: Calendar = .current) -> LedgerResult {
        let (blocks, activities) = project(focusBlocks: focusBlocks, tasks: tasks, conversations: conversations,
                                           meetings: meetings, calendar: calendar)
        return TimeLedger.compute(blocks: blocks, activities: activities, interval: interval, calendar: calendar)
    }

    /// Per-focus-block net-remaining hours (`FocusBlock.id` → net), from the canonical ledger. Used by the
    /// Tasks Time column and the task detail Time Log so a task's focus-block time reflects the dynamic net.
    static func blockNet(focusBlocks: [FocusBlock], tasks: [Task], conversations: [EmailConversation],
                         meetings: [Minutes], calendar: Calendar = .current) -> [UUID: Double] {
        ledger(focusBlocks: focusBlocks, tasks: tasks, conversations: conversations,
               meetings: meetings, calendar: calendar).blockNet
    }

    // MARK: Diary (already-flattened day input)

    static func projectDiary(focusBlocks: [FocusBlock], taskEntries: [TaskTimeEntry], completedTasks: [Task],
                             meetings: [Minutes],
                             calendar: Calendar = .current) -> (blocks: [LedgerBlock], activities: [LedgerActivity]) {
        let ctx = Context(focusBlocks: focusBlocks, calendar: calendar)
        var activities: [LedgerActivity] = []
        // The day's time entries are already day-filtered by the caller; attribute each to its owner's
        // project — a conversation (conversation-owned email time), else a legacy email, else its task.
        for e in taskEntries {
            let names: [String]
            if let convo = e.conversation { names = convo.projects.map(\.name) }
            else if let email = e.email { names = email.projects.map(\.name) }
            else { names = [e.task?.project?.name].compactMap { $0 } }
            activities.append(ctx.entry(id: e.id.uuidString, date: e.date, hours: e.duration.hoursNormalized, projects: names))
        }
        for task in completedTasks where task.timeEntries.isEmpty {
            if let c = task.completedAt, let d = task.duration {
                activities.append(ctx.legacyTask(id: task.id.uuidString, completedAt: c, hours: d.hoursNormalized,
                                                 projects: [task.project?.name].compactMap { $0 }))
            }
        }
        activities += meetingActivities(meetings, ctx)
        return (ctx.blocks, activities)
    }

    static func diaryLedger(focusBlocks: [FocusBlock], taskEntries: [TaskTimeEntry], completedTasks: [Task],
                            meetings: [Minutes], calendar: Calendar = .current) -> LedgerResult {
        let (blocks, activities) = projectDiary(focusBlocks: focusBlocks, taskEntries: taskEntries,
                                                completedTasks: completedTasks, meetings: meetings, calendar: calendar)
        return TimeLedger.compute(blocks: blocks, activities: activities, calendar: calendar)
    }

    // MARK: Shared

    // A conversation OWNS its logged time, attributed to the conversation's project(s) at each entry's date.
    private static func conversationActivities(_ conversations: [EmailConversation], _ ctx: Context) -> [LedgerActivity] {
        conversations.flatMap { convo -> [LedgerActivity] in
            let names = convo.projects.map(\.name)
            return convo.timeEntries.map {
                ctx.entry(id: $0.id.uuidString, date: $0.date, hours: $0.duration.hoursNormalized, projects: names)
            }
        }
    }

    private static func meetingActivities(_ meetings: [Minutes], _ ctx: Context) -> [LedgerActivity] {
        meetings.flatMap { m -> [LedgerActivity] in
            guard let hours = m.duration?.hoursNormalized, hours > 0 else { return [] }
            return ctx.meetingSplit(id: m.id.uuidString, start: m.meetingAt, hours: hours,
                                    projects: m.projects.map(\.name))
        }
    }

    // Membership/fold context built once per projection.
    private struct Context {
        let blocks: [LedgerBlock]
        private let blocksByDay: [Date: [FocusBlock]]
        private let calendar: Calendar

        init(focusBlocks: [FocusBlock], calendar: Calendar) {
            self.calendar = calendar
            var byDay: [Date: [FocusBlock]] = [:]
            var ledgerBlocks: [LedgerBlock] = []
            for fb in focusBlocks {
                guard let d = fb.dayRecord?.date else { continue }
                byDay[calendar.startOfDay(for: d), default: []].append(fb)
                ledgerBlocks.append(LedgerBlock(id: fb.id, date: WeekendPolicy.workWeekday(for: d, calendar: calendar),
                                                capacityHours: fb.duration.hoursNormalized,
                                                projectName: fb.project?.name ?? fb.task?.project?.name,
                                                isOvertime: fb.isOvertime))
            }
            blocks = ledgerBlocks
            blocksByDay = byDay
        }

        private func containing(_ date: Date) -> FocusBlock? {
            FocusBlockAssignment.containingBlock(for: date, blocks: blocksByDay[calendar.startOfDay(for: date)] ?? [],
                                                 calendar: calendar)
        }
        private func fold(_ date: Date) -> Date { WeekendPolicy.workWeekday(for: date, calendar: calendar) }
        private func isWeekend(_ date: Date) -> Bool { WeekendPolicy.isWeekend(date, calendar: calendar) }

        func entry(id: String, date: Date, hours: Double, projects: [String]) -> LedgerActivity {
            let weekend = isWeekend(date)
            let block = weekend ? nil : containing(date)
            return LedgerActivity(sourceKey: id, date: fold(date), hours: hours, projectNames: projects,
                                  blockID: block?.id, isOvertime: weekend || (block?.isOvertime ?? false))
        }
        func legacyTask(id: String, completedAt: Date, hours: Double, projects: [String]) -> LedgerActivity {
            LedgerActivity(sourceKey: id, date: fold(completedAt), hours: hours, projectNames: projects,
                           blockID: nil, isOvertime: isWeekend(completedAt))
        }
        // A weekday meeting is split across the day's standard blocks by the portion in each slot (so a meeting
        // spanning 12:30 reduces each block's net by only its part — not double-counted at full duration in both);
        // any part covered by no block is a standalone-standard remainder. A weekend meeting is overtime, whole.
        func meetingSplit(id: String, start: Date, hours: Double, projects: [String]) -> [LedgerActivity] {
            let folded = fold(start)
            if isWeekend(start) {
                return [LedgerActivity(sourceKey: id, date: folded, hours: hours, projectNames: projects,
                                       blockID: nil, isOvertime: true)]
            }
            let dayBlocks = (blocksByDay[calendar.startOfDay(for: start)] ?? []).filter { !$0.isOvertime }
            guard !dayBlocks.isEmpty else {
                return [LedgerActivity(sourceKey: id, date: folded, hours: hours, projectNames: projects,
                                       blockID: nil, isOvertime: false)]
            }
            var activities: [LedgerActivity] = []
            var covered = 0.0
            for fb in dayBlocks {
                let overlap = MeetingSlotHours.overlapHours(start: start, durationHours: hours,
                                                            slot: fb.slot, on: start, calendar: calendar)
                guard overlap > 0 else { continue }
                covered += overlap
                activities.append(LedgerActivity(sourceKey: "\(id)#\(fb.id.uuidString)", date: folded,
                                                 hours: overlap, projectNames: projects,
                                                 blockID: fb.id, isOvertime: false))
            }
            let remainder = hours - covered
            if remainder > 0.0001 {
                activities.append(LedgerActivity(sourceKey: "\(id)#rest", date: folded, hours: remainder,
                                                 projectNames: projects, blockID: nil, isOvertime: false))
            }
            return activities.isEmpty
                ? [LedgerActivity(sourceKey: id, date: folded, hours: hours, projectNames: projects,
                                  blockID: nil, isOvertime: false)]
                : activities
        }
    }
}
