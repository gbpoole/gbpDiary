import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct WorkspaceModelTests {

    // MARK: - Per-tab history navigation

    @Test func tabState_navigate_pushesHistoryAndEnablesBack() {
        let state = WorkspaceTabState(.diary)
        #expect(state.current == .diary)
        #expect(!state.canGoBack)

        state.navigate(to: .projects)
        #expect(state.current == .projects)
        #expect(state.canGoBack)
        #expect(!state.canGoForward)
    }

    @Test func tabState_navigate_toCurrentIsNoOp() {
        let state = WorkspaceTabState(.diary)
        state.navigate(to: .diary)
        #expect(!state.canGoBack)  // no duplicate history entry
    }

    @Test func tabState_backForward_traversesHistory() {
        let state = WorkspaceTabState(.diary)
        state.navigate(to: .projects)
        state.navigate(to: .tasks)

        state.goBack()
        #expect(state.current == .projects)
        #expect(state.canGoForward)

        state.goForward()
        #expect(state.current == .tasks)
        #expect(!state.canGoForward)
    }

    @Test func tabState_navigateAfterBack_truncatesForwardHistory() {
        let state = WorkspaceTabState(.diary)
        state.navigate(to: .projects)
        state.goBack()               // back to diary
        state.navigate(to: .tasks)   // should drop the forward (.projects) entry
        #expect(state.current == .tasks)
        #expect(!state.canGoForward)
        state.goBack()
        #expect(state.current == .diary)
    }

    // MARK: - Multi-tab model

    @Test func openInNewTab_addsAndActivates() {
        let ws = WorkspaceModel()
        #expect(ws.tabs.count == 1)
        ws.openInNewTab(.tasks)
        #expect(ws.tabs.count == 2)
        #expect(ws.active.current == .tasks)
    }

    @Test func openEmailExplorerInNewTab_alwaysCreatesConfiguredIndependentChatTab() {
        let ws = WorkspaceModel()
        let firstEmail = email(id: "1")
        let secondEmail = email(id: "2")

        ws.openEmailExplorerInNewTab(for: firstEmail)
        let firstChat = ws.active
        ws.openEmailExplorerInNewTab(for: secondEmail)
        let secondChat = ws.active

        #expect(ws.tabs.count == 3)
        #expect(firstChat.current == .chat)
        #expect(secondChat.current == .chat)
        #expect(firstChat.id != secondChat.id)
        #expect(firstChat.chatState !== secondChat.chatState)
        #expect(firstChat.chatState.mode == .emailExplorerLab)
        #expect(firstChat.chatState.selectedEmailID == firstEmail.persistentModelID)
        #expect(secondChat.chatState.selectedEmailID == secondEmail.persistentModelID)

        firstChat.chatState.mode = .database
        #expect(secondChat.chatState.mode == .emailExplorerLab)
    }

    // MARK: - Curation sessions

    /// The curation tab is an entity tab keyed by its ROOT project, so it reuses/closes like the others
    /// and lives under the Projects sidebar category.
    @Test func curationTab_focusOrOpenReusesAndCloseEntityCloses() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let project = Project(name: "Apollo")
        context.insert(project)
        try context.save()
        let pid = project.persistentModelID

        let ws = WorkspaceModel()
        ws.focusOrOpen(.curation(pid))
        #expect(ws.active.current == .curation(pid))
        #expect(ws.active.current.category == .projects)
        let count = ws.tabs.count

        ws.focusOrOpen(.curation(pid))
        #expect(ws.tabs.count == count)          // reused, not duplicated

        #expect(ws.references(pid))
        ws.closeEntity(pid)
        #expect(!ws.tabs.contains { $0.current == .curation(pid) })
    }

    /// A curation tab survives a session save/restore by the root project's stable UUID.
    @Test func snapshot_capturesCurationEntity_andRestoresIt() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let project = Project(name: "Apollo")
        context.insert(project)
        try context.save()

        let ws = WorkspaceModel()
        ws.focusOrOpen(.curation(project.persistentModelID))
        let snapshot = ws.snapshot(using: context)

        let restored = WorkspaceModel()
        restored.restore(snapshot, using: context)
        #expect(restored.tabs.contains { $0.current == .curation(project.persistentModelID) })
    }

    /// Walk position is per tab, so switching away and back resumes where the session was.
    @Test func curationIndex_isHeldPerTab() {
        let ws = WorkspaceModel()
        let first = ws.active
        first.curationIndex = 3
        ws.openInNewTab(.projects)
        #expect(ws.active.curationIndex == 0)    // the new tab has its own position
        ws.selectTab(at: 0)
        #expect(ws.active.curationIndex == 3)
    }

    // MARK: - Subtask breakdown drafts

    /// A half-typed breakdown outline must survive switching tabs: the tab's content view is torn down
    /// and rebuilt, so the draft is held on the tab state rather than in @State.
    @Test func breakdownDraft_survivesSwitchingTabsAndComingBack() {
        let ws = WorkspaceModel()
        let taskID = UUID()
        let taskTab = ws.active
        taskTab.breakdownDrafts[taskID] = "Write changelog\n    Collect PRs"

        ws.openInNewTab(.projects)
        #expect(ws.active !== taskTab)
        ws.selectTab(at: 0)

        #expect(ws.active === taskTab)
        #expect(ws.active.breakdownDrafts[taskID] == "Write changelog\n    Collect PRs")
    }

    /// Drafts are per task, so two tasks open in one tab don't share an outline.
    @Test func breakdownDrafts_areKeyedPerTask() {
        let state = WorkspaceTabState(.diary)
        let a = UUID(), b = UUID()
        state.breakdownDrafts[a] = "alpha"
        state.breakdownDrafts[b] = "beta"
        #expect(state.breakdownDrafts[a] == "alpha")
        #expect(state.breakdownDrafts[b] == "beta")
        #expect(state.breakdownDrafts[UUID()] == nil)
    }

    /// Session-only, like chatState: a draft is working state, not something to restore at launch.
    @Test func breakdownDraft_isNotPersistedInTheSnapshot() throws {
        let ws = WorkspaceModel()
        ws.active.breakdownDrafts[UUID()] = "unsaved outline"
        let container = try TestModelContainer.make()
        let snapshot = ws.snapshot(using: ModelContext(container))
        let json = try JSONEncoder().encode(snapshot)
        let text = String(decoding: json, as: UTF8.self)
        #expect(!text.contains("unsaved outline"))
    }

    @Test func chatState_survivesNavigationWithinItsWorkspaceTab() {
        let ws = WorkspaceModel()
        ws.navigate(to: .chat)
        let state = ws.active.chatState
        state.draft = "unfinished question"

        ws.navigate(to: .projects)
        ws.active.goBack()

        #expect(ws.active.current == .chat)
        #expect(ws.active.chatState === state)
        #expect(ws.active.chatState.draft == "unfinished question")
    }

    @Test func chatState_changingEmailClearsTransientLabDataButKeepsPrompt() {
        let state = ChatState()
        let first = email(id: "first")
        let second = email(id: "second")
        state.selectEmail(first.persistentModelID)
        state.lab.instructions = "Keep this experiment prompt"
        state.lab.body = "private transient body"
        state.lab.candidates = [ChatLabCandidate(summary: "Candidate")]

        state.selectEmail(second.persistentModelID)

        #expect(state.selectedEmailID == second.persistentModelID)
        #expect(state.lab.body == nil)
        #expect(state.lab.candidates.isEmpty)
        #expect(state.lab.instructions == "Keep this experiment prompt")
    }

    @Test func chatState_selectionRevision_rejectsOldAAfterAtoBtoA() {
        let state = ChatState()
        let first = email(id: "first")
        let second = email(id: "second")
        let firstID = first.persistentModelID

        state.selectEmail(firstID)
        let oldRevision = state.selectedEmailRevision
        state.selectEmail(second.persistentModelID)
        state.selectEmail(firstID)

        #expect(state.selectedEmailRevision > oldRevision)
        #expect(!state.isCurrentEmailRequest(firstID, revision: oldRevision))
        #expect(state.isCurrentEmailRequest(firstID, revision: state.selectedEmailRevision))
    }

    @Test func chatState_staleLabFinish_doesNotClearNewerSpinner() {
        let state = ChatState()
        let selected = email(id: "selected").persistentModelID
        state.selectEmail(selected)
        let revision = state.selectedEmailRevision
        state.lab.requestToken &+= 1
        let oldToken = state.lab.requestToken
        state.lab.isGenerating = true

        state.lab.requestToken &+= 1
        let newToken = state.lab.requestToken
        state.finishLabGeneration(selected, revision: revision, token: oldToken)

        #expect(state.lab.isGenerating)
        #expect(state.isCurrentLabRequest(selected, revision: revision, token: newToken))
    }

    @Test func chatState_clearChat_invalidatesInFlightAnswer() {
        let state = ChatState()
        state.messages = [ChatMessage(role: .user, content: "Question")]
        state.pendingQuestion = "Question"
        state.isAnswering = true
        state.answerRequestToken = 4
        let oldToken = state.answerRequestToken

        state.clearChat()

        #expect(state.messages.isEmpty)
        #expect(state.pendingQuestion.isEmpty)
        #expect(!state.isAnswering)
        #expect(!state.isCurrentAnswerRequest(oldToken))
    }

    @Test func chatState_answerRequest_isConsumedOnlyOnce() {
        let state = ChatState()
        state.pendingQuestion = "Question"
        state.answerRequestToken = 3

        #expect(state.beginAnswerRequest(3) == "Question")
        #expect(state.pendingQuestion.isEmpty)
        #expect(state.isAnswering)
        state.isAnswering = false
        #expect(state.beginAnswerRequest(3) == nil)
    }

    @Test func focusOrOpen_activatesExistingTabShowingDestination() {
        let ws = WorkspaceModel()
        ws.openInNewTab(.tasks)       // tab 2, active
        ws.openInNewTab(.projects)    // tab 3, active
        ws.focusOrOpen(.tasks)        // existing tab shows .tasks → activate, no new tab
        #expect(ws.tabs.count == 3)
        #expect(ws.active.current == .tasks)
    }

    @Test func focusOrOpen_opensNewTabWhenNoneShowsDestination() {
        let ws = WorkspaceModel()
        ws.focusOrOpen(.people)       // no tab currently shows .people
        #expect(ws.tabs.count == 2)
        #expect(ws.active.current == .people)
    }

    @Test func closeTab_reassignsActive() {
        let ws = WorkspaceModel()
        ws.openInNewTab(.tasks)
        let tasksId = ws.active.id
        ws.closeTab(tasksId)
        #expect(ws.tabs.count == 1)
        #expect(ws.active.current == .diary)
    }

    @Test func closeTab_lastTab_recreatesDiary() {
        let ws = WorkspaceModel()
        ws.closeTab(ws.active.id)
        #expect(ws.tabs.count == 1)
        #expect(ws.active.current == .diary)
    }

    @Test func moveTab_reordersAndPreservesActive() {
        let ws = WorkspaceModel()      // [diary]
        ws.openInNewTab(.tasks)        // [diary, tasks]
        ws.openInNewTab(.projects)     // [diary, tasks, projects], active = projects
        let projectsId = ws.active.id

        ws.moveTab(id: projectsId, toIndex: 0)   // drag projects to the front
        #expect(ws.tabs.map(\.current) == [.projects, .diary, .tasks])
        #expect(ws.activeId == projectsId)       // active tab unchanged by reordering
        #expect(ws.tabs.first?.id == projectsId)
    }

    // MARK: - Safari-like tab shortcuts

    @Test func newTab_opensAndActivatesDiaryTab() {
        let ws = WorkspaceModel()
        ws.openInNewTab(.tasks)          // 2 tabs, tasks active
        ws.newTab()
        #expect(ws.tabs.count == 3)
        #expect(ws.active.current == .diary)
        #expect(ws.activeIndex == 2)
    }

    @Test func closeActiveTab_closesCurrentAndReassigns() {
        let ws = WorkspaceModel()
        ws.openInNewTab(.tasks)          // active = tasks (index 1)
        ws.closeActiveTab()
        #expect(ws.tabs.count == 1)
        #expect(ws.active.current == .diary)
    }

    @Test func selectNextTab_wrapsAround() {
        let ws = WorkspaceModel()        // diary (0)
        ws.openInNewTab(.tasks)          // tasks (1)
        ws.openInNewTab(.projects)       // projects (2), active
        ws.selectNextTab()               // wraps 2 → 0
        #expect(ws.activeIndex == 0)
        ws.selectNextTab()               // 0 → 1
        #expect(ws.active.current == .tasks)
    }

    @Test func selectPreviousTab_wrapsAround() {
        let ws = WorkspaceModel()        // diary (0), active
        ws.openInNewTab(.tasks)          // tasks (1)
        ws.openInNewTab(.projects)       // projects (2)
        ws.selectTab(at: 0)              // back to diary
        ws.selectPreviousTab()           // wraps 0 → 2
        #expect(ws.activeIndex == 2)
        #expect(ws.active.current == .projects)
    }

    @Test func selectNextPrevious_singleTab_isNoOp() {
        let ws = WorkspaceModel()
        ws.selectNextTab()
        ws.selectPreviousTab()
        #expect(ws.activeIndex == 0)
        #expect(ws.tabs.count == 1)
    }

    @Test func selectTabAtIndex_activatesOrIgnoresOutOfRange() {
        let ws = WorkspaceModel()
        ws.openInNewTab(.tasks)          // index 1
        ws.openInNewTab(.projects)       // index 2, active
        ws.selectTab(at: 0)
        #expect(ws.active.current == .diary)
        ws.selectTab(at: 9)              // out of range → no change
        #expect(ws.active.current == .diary)
    }

    @Test func selectLastTab_activatesFinalTab() {
        let ws = WorkspaceModel()
        ws.openInNewTab(.tasks)
        ws.openInNewTab(.projects)       // last
        ws.selectTab(at: 0)              // move off the last
        ws.selectLastTab()
        #expect(ws.activeIndex == 2)
        #expect(ws.active.current == .projects)
    }

    // MARK: - Return to previous tab (MRU back-stack)

    @Test func returnToPreviousTab_progressivelyWalksBack() {
        let ws = WorkspaceModel()            // diary, active
        let diaryId = ws.activeId
        ws.openInNewTab(.tasks)              // tasks, active (pushes diary)
        let tasksId = ws.activeId
        ws.openInNewTab(.projects)           // projects, active (pushes tasks)
        ws.returnToPreviousTab()             // → tasks
        #expect(ws.activeId == tasksId)
        ws.returnToPreviousTab()             // → diary (progressive)
        #expect(ws.activeId == diaryId)
    }

    @Test func returnToPreviousTab_emptyStack_isNoOp() {
        let ws = WorkspaceModel()            // single tab, nothing to go back to
        let diaryId = ws.activeId
        ws.returnToPreviousTab()
        #expect(ws.activeId == diaryId)
        #expect(ws.tabs.count == 1)
    }

    @Test func returnToPreviousTab_recordsPositionalAndSelectionMoves() {
        let ws = WorkspaceModel()            // diary (0)
        ws.openInNewTab(.tasks)              // tasks (1)
        ws.openInNewTab(.projects)           // projects (2), active
        let projectsId = ws.activeId
        ws.selectTab(at: 0)                  // → diary (pushes projects)
        ws.returnToPreviousTab()             // → projects
        #expect(ws.activeId == projectsId)
    }

    @Test func returnToPreviousTab_mruDedups_noRepeatEntries() {
        let ws = WorkspaceModel()            // diary
        let diaryId = ws.activeId
        ws.openInNewTab(.tasks)              // tasks
        let tasksId = ws.activeId
        ws.activate(diaryId)                 // → diary (pushes tasks)
        ws.activate(tasksId)                 // → tasks (pushes diary; tasks de-duped)
        ws.returnToPreviousTab()             // → diary
        #expect(ws.activeId == diaryId)
        ws.returnToPreviousTab()             // stack now empty → stays
        #expect(ws.activeId == diaryId)
    }

    @Test func closeTab_returnsToTabItWasOpenedFrom_notPositionalNeighbour() {
        let ws = WorkspaceModel()            // diary (0)
        let diaryId = ws.activeId
        ws.openInNewTab(.projects)           // projects (1)
        ws.activate(diaryId)                 // navigate back to diary (active)
        ws.openInNewTab(.tasks)              // tasks (2), opened from diary — active third tab
        ws.closeActiveTab()                  // ⌘W on the third tab
        #expect(ws.activeId == diaryId)      // returns to diary (the opener), not the neighbour (projects)
    }

    @Test func returnToPreviousTab_skipsAndPurgesClosedTabs() {
        let ws = WorkspaceModel()            // diary
        let diaryId = ws.activeId
        ws.openInNewTab(.tasks)              // tasks (pushes diary)
        let tasksId = ws.activeId
        ws.openInNewTab(.projects)           // projects (pushes tasks); active
        ws.closeTab(tasksId)                 // remove tasks from the back-stack
        ws.returnToPreviousTab()             // skips the closed tasks tab → diary
        #expect(ws.activeId == diaryId)
    }

    // MARK: - Category mapping

    @Test func entityTab_reportsOwningCategory() {
        #expect(WorkspaceTab.tasks.category == .tasks)
        #expect(WorkspaceCategory.images.tab == .images)
    }

    // MARK: - Session persistence

    private func emptyTasksSnapshot() -> TasksFilterSnapshot {
        TasksFilterSnapshot(activeFilterIds: [], searchText: "", sortColumnID: "urgency",
                            sortAscending: false, dateRangeStart: nil, dateRangeEnd: nil, datePreset: nil)
    }
    private func defaultDiarySnapshot() -> DiarySnapshot {
        DiarySnapshot(date: FixedDates.reference, mode: "Day", tracksToday: true)
    }

    @Test func restore_rebuildsCategoryTabsActiveAndFilters() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let ws = WorkspaceModel()
        let snap = WorkspaceSnapshot(tabs: [
            TabSnapshot(history: [.page("diary")], index: 0,
                        diary: DiarySnapshot(date: FixedDates.reference, mode: "Week", tracksToday: false),
                        tasksFilter: emptyTasksSnapshot(), pageFilters: [:]),
            TabSnapshot(history: [.page("projects")], index: 0, diary: defaultDiarySnapshot(),
                        tasksFilter: emptyTasksSnapshot(),
                        pageFilters: ["Projects": ListFilterSnapshot(activeFilterIds: ["status.active"],
                                                                     searchText: "foo", sortColumnID: "stream", sortAscending: false)]),
        ], activeIndex: 1)
        ws.restore(snap, using: ctx)
        #expect(ws.tabs.count == 2)
        #expect(ws.tabs[0].current == .diary)
        #expect(ws.tabs[0].diaryState.mode == .week)
        #expect(ws.tabs[0].diaryState.currentDate == FixedDates.reference)
        #expect(ws.active.current == .projects)
        let pf = ws.tabs[1].pageFilter(for: .projects)
        #expect(pf.searchText == "foo")
        #expect(pf.sortColumnID == "stream")
        #expect(pf.sortAscending == false)
    }

    @Test func restore_chatStartsWithDefaultSessionOnlyState() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let ws = WorkspaceModel()
        ws.openInNewTab(.chat)
        ws.active.chatState.mode = .database
        ws.active.chatState.selectEmail(email(id: "selected").persistentModelID)
        let snap = WorkspaceSnapshot(tabs: [
            TabSnapshot(history: [.page("chat")], index: 0, diary: defaultDiarySnapshot(),
                        tasksFilter: emptyTasksSnapshot(), pageFilters: [:]),
        ], activeIndex: 0)

        ws.restore(snap, using: ctx)

        #expect(ws.active.current == .chat)
        #expect(ws.active.chatState.mode == .database)
        #expect(ws.active.chatState.selectedEmailID == nil)
        #expect(ws.active.chatState.messages.isEmpty)
    }

    @Test func restore_dropsTabWhoseEntityIsMissing() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let ws = WorkspaceModel()
        let snap = WorkspaceSnapshot(tabs: [
            TabSnapshot(history: [.page("tasks")], index: 0, diary: defaultDiarySnapshot(),
                        tasksFilter: emptyTasksSnapshot(), pageFilters: [:]),
            TabSnapshot(history: [.entity(kind: "project", id: UUID())], index: 0, diary: defaultDiarySnapshot(),
                        tasksFilter: emptyTasksSnapshot(), pageFilters: [:]),
        ], activeIndex: 1)
        ws.restore(snap, using: ctx)
        #expect(ws.tabs.count == 1)               // the unresolved entity tab is dropped
        #expect(ws.tabs[0].current == .tasks)
    }

    @Test func restore_nilSnapshot_keepsCurrentTabs() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let ws = WorkspaceModel()
        ws.openInNewTab(.tasks)
        ws.restore(nil, using: ctx)
        #expect(ws.tabs.count == 2)               // unchanged
    }

    @Test func snapshot_capturesEntityUUID_andRestoresIt() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let project = Project(name: "P")
        ctx.insert(project)
        try ctx.save()                            // permanent id before using persistentModelID / fetch
        let ws = WorkspaceModel()
        ws.openInNewTab(.project(project.persistentModelID))
        let snap = ws.snapshot(using: ctx)
        #expect(snap.tabs.contains { $0.history.contains(.entity(kind: "project", id: project.id)) })

        let ws2 = WorkspaceModel()
        ws2.restore(snap, using: ctx)
        #expect(ws2.tabs.contains { $0.current == .project(project.persistentModelID) })
    }

    // MARK: - Task detail tab

    @Test func task_tab_focusOrOpenReusesAndCloseEntityCloses() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let t = Task(summary: "T")
        ctx.insert(t)
        try ctx.save()
        let ws = WorkspaceModel()
        ws.focusOrOpen(.task(t.persistentModelID))
        #expect(ws.active.current == .task(t.persistentModelID))
        let count = ws.tabs.count
        ws.focusOrOpen(.task(t.persistentModelID))   // already shown → reuse, no new tab
        #expect(ws.tabs.count == count)
        #expect(ws.references(t.persistentModelID))
        ws.closeEntity(t.persistentModelID)
        #expect(!ws.references(t.persistentModelID))
    }

    @Test func snapshot_capturesTaskEntity_andRestoresIt() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let t = Task(summary: "T")
        ctx.insert(t)
        try ctx.save()
        let ws = WorkspaceModel()
        ws.openInNewTab(.task(t.persistentModelID))
        let snap = ws.snapshot(using: ctx)
        #expect(snap.tabs.contains { $0.history.contains(.entity(kind: "task", id: t.id)) })

        let ws2 = WorkspaceModel()
        ws2.restore(snap, using: ctx)
        #expect(ws2.tabs.contains { $0.current == .task(t.persistentModelID) })
    }

    @Test func revealTimeEntry_focusesDiaryOnEntryDayWithScrollTarget() {
        let ws = WorkspaceModel()
        ws.openInNewTab(.tasks)   // active tab is not the diary
        let entry = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 1, unit: .h))
        ws.revealTimeEntry(entry)
        #expect(ws.active.current == .diary)
        #expect(ws.active.diaryState.mode == .day)
        #expect(ws.active.diaryState.currentDate == WeekendPolicy.weekday(for: FixedDates.reference))
        #expect(ws.active.diaryState.scrollTargetEntryId == entry.id)
    }

    @Test func revealFocusBlock_focusesDiaryOnBlockDayWithScrollTarget() {
        let ws = WorkspaceModel()
        ws.openInNewTab(.tasks)
        let block = FocusBlock(duration: Duration(value: 7.6, unit: .h))
        block.dayRecord = DayRecord(date: FixedDates.reference)
        ws.revealFocusBlock(block)
        #expect(ws.active.current == .diary)
        #expect(ws.active.diaryState.mode == .day)
        #expect(ws.active.diaryState.currentDate == WeekendPolicy.weekday(for: FixedDates.reference))
        #expect(ws.active.diaryState.scrollTargetBlockId == block.id)
    }

    private func email(id: String) -> EmailMessage {
        EmailMessage(messageId: id, account: "account", mailbox: "INBOX", direction: .inbox,
                     fromAddress: "sender@example.com", fromName: "Sender", subject: "Subject", date: FixedDates.reference)
    }
}
