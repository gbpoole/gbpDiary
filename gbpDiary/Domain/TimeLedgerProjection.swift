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
        meetings.compactMap { m in
            guard let hours = m.duration?.hoursNormalized, hours > 0 else { return nil }
            return ctx.meeting(id: m.id.uuidString, date: m.meetingAt, hours: hours, projects: m.projects.map(\.name))
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
        // Meetings are overtime only on weekends; a weekday meeting reduces its standard block's net, else it
        // is standalone-standard (the diary never puts meetings in an evening/overtime block).
        func meeting(id: String, date: Date, hours: Double, projects: [String]) -> LedgerActivity {
            let weekend = isWeekend(date)
            let cb = weekend ? nil : containing(date)
            let block = (cb?.isOvertime ?? false) ? nil : cb
            return LedgerActivity(sourceKey: id, date: fold(date), hours: hours, projectNames: projects,
                                  blockID: block?.id, isOvertime: weekend)
        }
    }
}
