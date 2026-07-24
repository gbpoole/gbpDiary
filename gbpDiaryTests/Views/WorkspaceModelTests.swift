import Foundation
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

    // MARK: - Category mapping

    @Test func entityTab_reportsOwningCategory() {
        #expect(WorkspaceTab.tasks.category == .tasks)
        #expect(WorkspaceCategory.images.tab == .images)
    }
}
