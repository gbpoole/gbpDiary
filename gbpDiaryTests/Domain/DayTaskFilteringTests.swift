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

    @Test func taskEntryIds_includesDayRecordOwnedTasks() {
        let day = DayRecord(date: FixedDates.dayStart())
        let task = Task(summary: "owned")
        day.tasks = [task]

        let ids = DayTaskFiltering.taskEntryIds(from: day)
        #expect(ids == Set([task.persistentModelID]))
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

    @Test func inbox_includesUnassignedTopLevelActiveTasks() {
        let unassigned = Task(summary: "inbox", status: .todo)

        let withProject = Task(summary: "has-project", status: .todo)
        withProject.project = Project(name: "P")

        let withAssignee = Task(summary: "has-assignee", status: .todo)
        withAssignee.assignee = Person(name: "Alice")

        let child = Task(summary: "child", status: .todo)
        let parent = Task(summary: "parent")
        child.parent = parent

        let completed = Task(summary: "completed", status: .completed)

        let result = DayTaskFiltering.inboxTasks(
            allTasks: [unassigned, withProject, withAssignee, child, completed]
        )
        #expect(result.map(\.id) == [unassigned.id])
    }

    @Test func inbox_includesStartedButExcludesOtherStatuses() {
        let todo = Task(summary: "todo", status: .todo)
        let started = Task(summary: "started", status: .started)
        let cancelled = Task(summary: "cancelled", status: .cancelled)
        let followUp = Task(summary: "followup", status: .followUpPending)

        let result = DayTaskFiltering.inboxTasks(allTasks: [todo, started, cancelled, followUp])
        #expect(Set(result.map(\.id)) == Set([todo.id, started.id]))
    }
}
