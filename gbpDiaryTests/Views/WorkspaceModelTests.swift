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

    private func email(id: String) -> EmailMessage {
        EmailMessage(messageId: id, account: "account", mailbox: "INBOX", direction: .inbox,
                     fromAddress: "sender@example.com", fromName: "Sender", subject: "Subject", date: FixedDates.reference)
    }
}
