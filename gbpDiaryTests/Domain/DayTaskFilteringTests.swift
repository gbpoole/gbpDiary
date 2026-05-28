import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct DayTaskFilteringTests {
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
}
