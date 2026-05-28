import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct DayTaskFilteringTests {
    @Test func dayBounds_returnsStartOfDayAndNextDay() {
        let date = FixedDates.atHour(14)
        let bounds = DayTaskFiltering.dayBounds(for: date)

        #expect(bounds.dayStart == Calendar.current.startOfDay(for: date))
        #expect(bounds.dayEnd == Calendar.current.date(byAdding: .day, value: 1, to: bounds.dayStart))
    }

    @Test func taskEntryIds_collectsOnlyTaskBackedEntries() {
        let day = DayRecord(date: FixedDates.dayStart())
        let task = Task(summary: "mapped")
        let taskEntry = DayEntry(kind: .task, sortOrder: 0)
        taskEntry.task = task
        let noteEntry = DayEntry(kind: .note, sortOrder: 1)
        day.entries = [taskEntry, noteEntry]

        let ids = DayTaskFiltering.taskEntryIds(from: day)
        #expect(ids == Set([task.persistentModelID]))
    }

    @Test func followUpsDue_includesPendingBeforeDayEnd() {
        let dayStart = FixedDates.dayStart()
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let dueTask = Task(summary: "due", status: .followUpPending)
        dueTask.followUpAt = Calendar.current.date(byAdding: .hour, value: -1, to: dayEnd)

        let wrongStatus = Task(summary: "wrong", status: .todo)
        wrongStatus.followUpAt = Calendar.current.date(byAdding: .hour, value: -1, to: dayEnd)

        let afterBoundary = Task(summary: "late", status: .followUpPending)
        afterBoundary.followUpAt = dayEnd

        let result = DayTaskFiltering.followUpsDueTasks(allTasks: [dueTask, wrongStatus, afterBoundary], dayEnd: dayEnd)
        #expect(result.map(\.id) == [dueTask.id])
    }

    @Test func scheduled_excludesTasksAlreadyInEntries() {
        let dayStart = FixedDates.dayStart()
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let shown = Task(summary: "shown", status: .todo)
        shown.scheduledAt = FixedDates.atHour(10)
        let hidden = Task(summary: "hidden", status: .started)
        hidden.scheduledAt = FixedDates.atHour(11)

        let taskEntryIds = Set([hidden.persistentModelID])
        let result = DayTaskFiltering.scheduledTasks(
            allTasks: [shown, hidden],
            dayStart: dayStart,
            dayEnd: dayEnd,
            taskEntryIds: taskEntryIds
        )

        #expect(result.map(\.id) == [shown.id])
    }

    @Test func scheduled_requiresTodoOrStartedAndWithinDayBounds() {
        let dayStart = FixedDates.dayStart()
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let todoWithin = Task(summary: "todo-within", status: .todo)
        todoWithin.scheduledAt = FixedDates.atHour(9)

        let completedWithin = Task(summary: "completed-within", status: .completed)
        completedWithin.scheduledAt = FixedDates.atHour(10)

        let atEndBoundary = Task(summary: "at-end", status: .todo)
        atEndBoundary.scheduledAt = dayEnd

        let result = DayTaskFiltering.scheduledTasks(
            allTasks: [todoWithin, completedWithin, atEndBoundary],
            dayStart: dayStart,
            dayEnd: dayEnd,
            taskEntryIds: []
        )

        #expect(result.map(\.id) == [todoWithin.id])
    }

    @Test func backlog_requiresTopLevelTodoOrStartedBeforeDayStart() {
        let dayStart = FixedDates.dayStart()

        let topLevel = Task(summary: "ok", status: .todo)
        topLevel.scheduledAt = nil

        let scheduledToday = Task(summary: "today", status: .todo)
        scheduledToday.scheduledAt = dayStart

        let parent = Task(summary: "parent")
        let child = Task(summary: "child", status: .todo)
        child.parent = parent

        let result = DayTaskFiltering.backlogTasks(allTasks: [topLevel, scheduledToday, child], dayStart: dayStart)
        #expect(result.map(\.id) == [topLevel.id])
    }

    @Test func completedToday_includesOnlyWithinDayBounds() {
        let dayStart = FixedDates.dayStart()
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let included = Task(summary: "included", status: .completed)
        included.completedAt = FixedDates.atHour(16)

        let atEndBoundary = Task(summary: "excluded-end", status: .completed)
        atEndBoundary.completedAt = dayEnd

        let beforeDay = Task(summary: "excluded-before", status: .completed)
        beforeDay.completedAt = dayStart.addingTimeInterval(-1)

        let result = DayTaskFiltering.completedTodayTasks(
            allTasks: [included, atEndBoundary, beforeDay],
            dayStart: dayStart,
            dayEnd: dayEnd
        )
        #expect(result.map(\.id) == [included.id])
    }
}
