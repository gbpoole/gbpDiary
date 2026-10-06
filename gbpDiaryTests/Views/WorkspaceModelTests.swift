import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct WorkspaceModelTests {

    // MARK: - Fixture
    //
    // Tabs are entity-only now, so every tab test needs real models to key them on. `save()` matters:
    // `persistentModelID` is only permanent afterwards, and restore fetches by the model's UUID.

    private struct Fixture {
        let ctx: ModelContext
        let projectA: Project
        let projectB: Project
        let task: Task

        init() throws {
            ctx = ModelContext(try TestModelContainer.make())
            projectA = Project(name: "Apollo")
            projectB = Project(name: "Borealis")
            task = Task(summary: "T")
            ctx.insert(projectA); ctx.insert(projectB); ctx.insert(task)
            try ctx.save()
        }
        var a: WorkspaceTab { .project(projectA.persistentModelID) }
        var b: WorkspaceTab { .project(projectB.persistentModelID) }
        var t: WorkspaceTab { .task(task.persistentModelID) }
    }

    // MARK: - Panes vs tabs

    /// A workspace starts with no tabs at all: the Diary *pane* is what you see.
    @Test func freshWorkspace_showsTheDiaryPaneWithNoTabs() {
        let ws = WorkspaceModel()
        #expect(ws.tabs.isEmpty)
        #expect(ws.activeTab == nil)
        #expect(ws.selectedCategory == .diary)
    }

    /// Picking a sidebar category shows its pane and clears the active tab — a pane and a tab are
    /// alternatives, so there is only ever one "what am I looking at".
    @Test func select_showsThePaneAndClearsTheActiveTab() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        #expect(ws.activeTab != nil)

        ws.select(.tasks)
        #expect(ws.selectedCategory == .tasks)
        #expect(ws.activeTab == nil, "the pane is showing")
        #expect(ws.tabs.count == 1, "the tab stays open behind it")
    }

    /// …and activating a tab hides the pane again without disturbing the sidebar's remembered category.
    @Test func activatingATab_hidesThePaneButKeepsTheCategory() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        ws.select(.projects)
        ws.activate(ws.tabs[0].id)
        #expect(ws.activeTab?.tab == f.a)
        #expect(ws.selectedCategory == .projects, "returning to the pane lands where you left it")
        ws.showSelectedPane()
        #expect(ws.activeTab == nil)
    }

    /// Page state is single-instance now: one Diary, one Tasks filter, one Database Chat.
    @Test func pageState_isOnePerWorkspace() {
        let ws = WorkspaceModel()
        ws.tasksFilter.searchText = "urgent"
        ws.diaryState.mode = .week
        #expect(ws.tasksFilter.searchText == "urgent")
        #expect(ws.diaryState.mode == .week)
        // The same object every time, so edits on one surface are visible on the next.
        #expect(ws.pageFilter(for: .projects) === ws.pageFilter(for: .projects))
        #expect(ws.pageFilter(for: .projects) !== ws.pageFilter(for: .people))
    }

    // MARK: - Multi-tab model

    @Test func openInNewTab_addsAndActivates() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        #expect(ws.tabs.count == 1)
        #expect(ws.activeTab?.tab == f.a)
    }

    @Test func focusOrOpen_activatesExistingTabShowingEntity() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        ws.openInNewTab(f.b)
        ws.focusOrOpen(f.a)
        #expect(ws.tabs.count == 2, "reused, not duplicated")
        #expect(ws.activeTab?.tab == f.a)
    }

    @Test func focusOrOpen_opensNewTabWhenNoneShowsEntity() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.focusOrOpen(f.t)
        #expect(ws.tabs.count == 1)
        #expect(ws.activeTab?.tab == f.t)
    }

    @Test func closeTab_reassignsActive() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        ws.openInNewTab(f.b)
        ws.closeTab(ws.activeTab!.id)
        #expect(ws.tabs.count == 1)
        #expect(ws.activeTab?.tab == f.a)
    }

    /// Closing the last tab reveals the pane rather than manufacturing a replacement tab — there is
    /// always a category pane behind the strip, so nothing has to be invented.
    @Test func closeTab_lastTab_revealsThePane() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.select(.tasks)
        ws.openInNewTab(f.a)
        ws.closeTab(ws.activeTab!.id)
        #expect(ws.tabs.isEmpty)
        #expect(ws.activeTab == nil)
        #expect(ws.selectedCategory == .tasks)
    }

    @Test func moveTab_reordersAndPreservesActive() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        ws.openInNewTab(f.b)
        ws.openInNewTab(f.t)
        let taskId = ws.activeTab!.id

        ws.moveTab(id: taskId, toIndex: 0)
        #expect(ws.tabs.map(\.tab) == [f.t, f.a, f.b])
        #expect(ws.activeId == taskId, "active tab unchanged by reordering")
    }

    // MARK: - Safari-like tab shortcuts (entity tabs only)

    @Test func closeActiveTab_closesCurrentAndReassigns() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        ws.openInNewTab(f.b)
        ws.closeActiveTab()
        #expect(ws.tabs.count == 1)
        #expect(ws.activeTab?.tab == f.a)
    }

    /// ⌘W while a pane is showing does nothing: a pane isn't closable.
    @Test func closeActiveTab_whilePaneShowing_isNoOp() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        ws.select(.tasks)
        ws.closeActiveTab()
        #expect(ws.tabs.count == 1)
    }

    @Test func selectNextTab_wrapsAround() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        ws.openInNewTab(f.b)
        ws.openInNewTab(f.t)     // active, index 2
        ws.selectNextTab()       // wraps 2 → 0
        #expect(ws.activeIndex == 0)
    }

    @Test func selectPreviousTab_wrapsAround() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        ws.openInNewTab(f.b)
        ws.selectTab(at: 0)
        ws.selectPreviousTab()   // wraps 0 → 1
        #expect(ws.activeIndex == 1)
    }

    @Test func selectNextPrevious_singleTab_isNoOp() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        let id = ws.activeId
        ws.selectNextTab()
        ws.selectPreviousTab()
        #expect(ws.activeId == id)
    }

    @Test func selectTabAtIndex_activatesOrIgnoresOutOfRange() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        ws.openInNewTab(f.b)
        ws.selectTab(at: 0)
        #expect(ws.activeTab?.tab == f.a)
        ws.selectTab(at: 9)
        #expect(ws.activeTab?.tab == f.a, "out of range is a no-op")
    }

    @Test func selectLastTab_activatesFinalTab() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        ws.openInNewTab(f.b)
        ws.selectTab(at: 0)
        ws.selectLastTab()
        #expect(ws.activeIndex == 1)
        #expect(ws.activeTab?.tab == f.b)
    }

    // MARK: - Return to previous tab (MRU back-stack)

    @Test func returnToPreviousTab_progressivelyWalksBack() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        let aId = ws.activeId
        ws.openInNewTab(f.b)
        let bId = ws.activeId
        ws.openInNewTab(f.t)
        ws.returnToPreviousTab()
        #expect(ws.activeId == bId)
        ws.returnToPreviousTab()
        #expect(ws.activeId == aId)
    }

    @Test func returnToPreviousTab_emptyStack_isNoOp() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        let id = ws.activeId
        ws.returnToPreviousTab()
        #expect(ws.activeId == id)
    }

    @Test func returnToPreviousTab_recordsPositionalAndSelectionMoves() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        ws.openInNewTab(f.b)
        ws.openInNewTab(f.t)
        let tId = ws.activeId
        ws.selectTab(at: 0)          // pushes the task tab
        ws.returnToPreviousTab()
        #expect(ws.activeId == tId)
    }

    @Test func returnToPreviousTab_mruDedups_noRepeatEntries() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        let aId = ws.activeId
        ws.openInNewTab(f.b)
        let bId = ws.activeId
        ws.activate(aId!)
        ws.activate(bId!)
        ws.returnToPreviousTab()
        #expect(ws.activeId == aId)
        ws.returnToPreviousTab()     // stack empty → stays
        #expect(ws.activeId == aId)
    }

    @Test func closeTab_returnsToTabItWasOpenedFrom_notPositionalNeighbour() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        let aId = ws.activeId
        ws.openInNewTab(f.b)
        ws.activate(aId!)
        ws.openInNewTab(f.t)         // opened from A
        ws.closeActiveTab()
        #expect(ws.activeId == aId, "returns to the opener, not the neighbour")
    }

    @Test func returnToPreviousTab_skipsAndPurgesClosedTabs() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        let aId = ws.activeId
        ws.openInNewTab(f.b)
        let bId = ws.activeId
        ws.openInNewTab(f.t)
        ws.closeTab(bId!)
        ws.returnToPreviousTab()
        #expect(ws.activeId == aId)
    }

    // MARK: - Curation sessions

    @Test func curationTab_focusOrOpenReusesAndCloseEntityCloses() throws {
        let f = try Fixture()
        let pid = f.projectA.persistentModelID
        let ws = WorkspaceModel()
        ws.focusOrOpen(.curation(pid))
        #expect(ws.activeTab?.tab == .curation(pid))
        #expect(WorkspaceTab.curation(pid).category == .projects)

        ws.focusOrOpen(.curation(pid))
        #expect(ws.tabs.count == 1, "reused, not duplicated")
        #expect(ws.references(pid))
        ws.closeEntity(pid)
        #expect(!ws.tabs.contains { $0.tab == .curation(pid) })
    }

    @Test func snapshot_capturesCurationEntity_andRestoresIt() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.focusOrOpen(.curation(f.projectA.persistentModelID))
        let snapshot = ws.snapshot(using: f.ctx)

        let restored = WorkspaceModel()
        restored.restore(snapshot, using: f.ctx)
        #expect(restored.tabs.contains { $0.tab == .curation(f.projectA.persistentModelID) })
    }

    /// Walk position is per tab — two curation sessions don't share a place in their walks.
    @Test func curationIndex_isHeldPerTab() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(.curation(f.projectA.persistentModelID))
        ws.curationIndex = 3
        ws.openInNewTab(.curation(f.projectB.persistentModelID))
        #expect(ws.curationIndex == 0, "the new session has its own position")
        ws.selectTab(at: 0)
        #expect(ws.curationIndex == 3)
    }

    // MARK: - Email Explorer tabs

    /// The lab is its own tab kind, always fresh, because experiments are per-email and deliberately
    /// parallel — which the single Chat *pane* could not provide.
    @Test func openEmailExplorerInNewTab_alwaysCreatesAFreshConfiguredTab() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let first = email(id: "1"), second = email(id: "2")
        ctx.insert(first); ctx.insert(second)
        try ctx.save()

        let ws = WorkspaceModel()
        ws.openEmailExplorerInNewTab(for: first)
        let firstTab = ws.activeTab!
        ws.openEmailExplorerInNewTab(for: second)
        let secondTab = ws.activeTab!

        #expect(ws.tabs.count == 2)
        #expect(firstTab.id != secondTab.id)
        #expect(firstTab.chatState !== secondTab.chatState)
        #expect(firstTab.chatState.mode == .emailExplorerLab)
        #expect(firstTab.chatState.selectedEmailID == first.persistentModelID)
        #expect(secondTab.chatState.selectedEmailID == second.persistentModelID)

        // Independent: changing one experiment leaves the other alone.
        firstTab.chatState.mode = .database
        #expect(secondTab.chatState.mode == .emailExplorerLab)
        // …and the Chat pane's own state is a third, separate thing.
        #expect(ws.chatState !== firstTab.chatState)
        #expect(ws.chatState.mode == .database)
    }

    /// A lab tab holds only transient, unsaved experiment state, so restoring it would present an empty
    /// shell. It is deliberately dropped.
    @Test func emailExplorerTab_isNotRestored() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let e = email(id: "1")
        ctx.insert(e)
        try ctx.save()
        let ws = WorkspaceModel()
        ws.openEmailExplorerInNewTab(for: e)
        let snap = ws.snapshot(using: ctx)
        #expect(snap.entityTabs?.contains { $0.kind == "emailExplorer" } == true, "it IS written…")

        let restored = WorkspaceModel()
        restored.restore(snap, using: ctx)
        #expect(restored.tabs.isEmpty, "…but not rebuilt")
        #expect(restored.activeTab == nil)
    }

    // MARK: - Chat state (pane and lab share one type)

    @Test func chatState_changingEmailClearsTransientLabDataButKeepsPrompt() {
        let state = ChatState()
        let first = email(id: "first"), second = email(id: "second")
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
        let first = email(id: "first"), second = email(id: "second")
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

    // MARK: - Category mapping

    @Test func entityTab_reportsOwningCategory() throws {
        let f = try Fixture()
        #expect(f.t.category == .tasks)
        #expect(f.a.category == .projects)
        #expect(WorkspaceTab.emailExplorer(f.projectA.persistentModelID).category == .chat)
    }

    // MARK: - Session persistence

    @Test func snapshot_capturesSelectedCategoryActiveTabAndPageState() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.select(.projects)
        ws.openInNewTab(f.a)
        ws.openInNewTab(f.t)
        ws.selectTab(at: 0)
        ws.tasksFilter.searchText = "urgent"
        ws.boardPanelShown = true
        ws.pageFilter(for: .projects).searchText = "apollo"

        let snap = ws.snapshot(using: f.ctx)
        #expect(snap.selectedCategory == WorkspaceCategory.projects.rawValue)
        #expect(snap.entityTabs?.map(\.kind) == ["project", "task"])
        #expect(snap.activeTabIndex == 0)
        #expect(snap.tasksFilter?.searchText == "urgent")
        #expect(snap.boardPanelShown == true)
        #expect(snap.pageFilters?["Projects"]?.searchText == "apollo")

        let restored = WorkspaceModel()
        restored.restore(snap, using: f.ctx)
        #expect(restored.selectedCategory == .projects)
        #expect(restored.tabs.map(\.tab) == [f.a, f.t])
        #expect(restored.activeTab?.tab == f.a)
        #expect(restored.tasksFilter.searchText == "urgent")
        #expect(restored.boardPanelShown)
        #expect(restored.pageFilter(for: .projects).searchText == "apollo")
    }

    /// A pane showing and no tabs is a legitimate session, not an empty one.
    @Test func snapshot_withNoTabs_restoresThePane() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.select(.timesheet)
        let snap = ws.snapshot(using: f.ctx)

        let restored = WorkspaceModel()
        restored.restore(snap, using: f.ctx)
        #expect(restored.selectedCategory == .timesheet)
        #expect(restored.tabs.isEmpty)
        #expect(restored.activeTab == nil)
    }

    /// The migration that matters: a session saved while categories were tabs.
    @Test func restore_legacySnapshot_foldsIntoAPaneAndEntityTabs() throws {
        let f = try Fixture()
        let tasksSnap = TasksFilterSnapshot(activeFilterIds: [], searchText: "legacy",
                                            sortColumnID: "urgency", sortAscending: false,
                                            dateRangeStart: nil, dateRangeEnd: nil, datePreset: nil)
        let diarySnap = DiarySnapshot(date: FixedDates.reference, mode: "Week", tracksToday: false)
        let legacy = WorkspaceSnapshot(tabs: [
            TabSnapshot(history: [.page("tasks")], index: 0, diary: diarySnap,
                        tasksFilter: tasksSnap, pageFilters: [:]),
            TabSnapshot(history: [.entity(kind: "project", id: f.projectA.id)], index: 0,
                        diary: diarySnap, tasksFilter: tasksSnap, pageFilters: [:]),
        ], activeIndex: 0)

        let ws = WorkspaceModel()
        ws.restore(legacy, using: f.ctx)
        #expect(ws.selectedCategory == .tasks, "the active legacy tab was the Tasks page")
        #expect(ws.activeTab == nil, "so the pane is showing")
        #expect(ws.tabs.map(\.tab) == [f.a], "the other tab's entity survives as a tab")
        #expect(ws.tasksFilter.searchText == "legacy")
        #expect(ws.diaryState.mode == .week)
    }

    @Test func restore_dropsTabWhoseEntityIsMissing() throws {
        let f = try Fixture()
        let snap = WorkspaceSnapshot(
            selectedCategory: WorkspaceCategory.tasks.rawValue,
            entityTabs: [EntityTabSnapshot(kind: "project", id: UUID()),     // gone
                         EntityTabSnapshot(kind: "task", id: f.task.id)],
            activeTabIndex: 0)
        let ws = WorkspaceModel()
        ws.restore(snap, using: f.ctx)
        #expect(ws.tabs.map(\.tab) == [f.t])
        #expect(ws.activeTab == nil, "the tab that was active is gone, so the pane shows")
    }

    @Test func restore_nilSnapshot_keepsCurrentState() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)
        ws.restore(nil, using: f.ctx)
        #expect(ws.tabs.count == 1)
        #expect(ws.activeTab?.tab == f.a)
    }

    // MARK: - Task detail tab

    @Test func task_tab_focusOrOpenReusesAndCloseEntityCloses() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.focusOrOpen(f.t)
        #expect(ws.activeTab?.tab == f.t)
        ws.focusOrOpen(f.t)
        #expect(ws.tabs.count == 1)
        #expect(ws.references(f.task.persistentModelID))
        ws.closeEntity(f.task.persistentModelID)
        #expect(!ws.references(f.task.persistentModelID))
    }

    // MARK: - Revealing the diary

    @Test func revealTimeEntry_focusesDiaryPaneOnEntryDayWithScrollTarget() throws {
        let f = try Fixture()
        let ws = WorkspaceModel()
        ws.openInNewTab(f.a)       // a tab is covering the pane
        let entry = TaskTimeEntry(date: FixedDates.reference, duration: Duration(value: 1, unit: .h))
        ws.revealTimeEntry(entry)
        #expect(ws.selectedCategory == .diary)
        #expect(ws.activeTab == nil, "the diary is a pane, so the tab is dismissed")
        #expect(ws.diaryState.mode == .day)
        #expect(ws.diaryState.currentDate == WeekendPolicy.weekday(for: FixedDates.reference))
        #expect(ws.diaryState.scrollTargetEntryId == entry.id)
    }

    @Test func revealFocusBlock_focusesDiaryPaneOnBlockDayWithScrollTarget() {
        let ws = WorkspaceModel()
        let block = FocusBlock(duration: Duration(value: 7.6, unit: .h))
        block.dayRecord = DayRecord(date: FixedDates.reference)
        ws.revealFocusBlock(block)
        #expect(ws.selectedCategory == .diary)
        #expect(ws.diaryState.mode == .day)
        #expect(ws.diaryState.currentDate == WeekendPolicy.weekday(for: FixedDates.reference))
        #expect(ws.diaryState.scrollTargetBlockId == block.id)
    }

    private func email(id: String) -> EmailMessage {
        EmailMessage(messageId: id, account: "account", mailbox: "INBOX", direction: .inbox,
                     fromAddress: "sender@example.com", fromName: "Sender", subject: "Subject",
                     date: FixedDates.reference)
    }
}
