import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct WorkspaceSessionTests {

    // MARK: - Entity kinds

    @Test func entityKind_tokens() {
        // Every tab is an entity now, so the mapping is total — there is no page token any more.
        #expect(WorkspaceTabCoding.entityKind(for: .project(dummyID())) == "project")
        #expect(WorkspaceTabCoding.entityKind(for: .task(dummyID())) == "task")
        #expect(WorkspaceTabCoding.entityKind(for: .curation(dummyID())) == "curation")
        #expect(WorkspaceTabCoding.entityKind(for: .emailExplorer(dummyID())) == "emailExplorer")
    }

    // MARK: - Legacy page tokens (migration only)

    /// The old tab vocabulary still has to be readable, because a saved session names categories with it.
    @Test func legacyPageTokens_mapToCategories() {
        #expect(WorkspaceTabCoding.categoryToken(migrating: "diary") == WorkspaceCategory.diary.rawValue)
        #expect(WorkspaceTabCoding.categoryToken(migrating: "triage") == WorkspaceCategory.triage.rawValue)
        #expect(WorkspaceTabCoding.categoryToken(migrating: "content") == WorkspaceCategory.content.rawValue)
        #expect(WorkspaceTabCoding.categoryToken(migrating: "nonsense") == nil)
    }

    /// The board was its own tab two refactors ago; its token must still land on Tasks (whose panel hosts
    /// it) rather than nil, which would lose that tab's page state at restore.
    @Test func legacyBoardToken_migratesToTasks() {
        #expect(WorkspaceTabCoding.categoryToken(migrating: "board") == WorkspaceCategory.tasks.rawValue)
    }

    // MARK: - Legacy snapshot migration

    private func legacyTab(_ history: [TabDestination], index: Int = 0,
                           mode: String = "Day", board: Bool? = nil) -> TabSnapshot {
        TabSnapshot(history: history, index: index,
                    diary: DiarySnapshot(date: FixedDates.reference, mode: mode, tracksToday: false),
                    tasksFilter: TasksFilterSnapshot(activeFilterIds: ["preset.incomplete"], searchText: "q",
                                                     sortColumnID: "urgency", sortAscending: false,
                                                     dateRangeStart: nil, dateRangeEnd: nil, datePreset: nil),
                    pageFilters: ["Projects": ListFilterSnapshot(activeFilterIds: ["status.active"],
                                                                 searchText: "", sortColumnID: "name",
                                                                 sortAscending: true)],
                    boardPanelShown: board, boardFullWidth: board)
    }

    /// A session saved before categories became panes: the **active** tab decides the selected category,
    /// and its page state is the one kept (it is the only defensible choice among per-tab copies).
    @Test func migrated_takesCategoryAndPageStateFromTheActiveTab() {
        let snap = WorkspaceSnapshot(tabs: [legacyTab([.page("diary")]),
                                            legacyTab([.page("tasks")], mode: "Week", board: true)],
                                    activeIndex: 1)
        #expect(snap.isLegacy)
        let m = snap.migrated()
        #expect(m.selectedCategory == WorkspaceCategory.tasks.rawValue)
        #expect(m.diary?.mode == "Week")
        #expect(m.tasksFilter?.searchText == "q")
        #expect(m.pageFilters?["Projects"]?.activeFilterIds == ["status.active"])
        #expect(m.boardPanelShown == true)
        #expect(m.entityTabs == [], "category tabs are not tabs any more")
        #expect(m.activeTabIndex == nil, "the active tab was a category, so the pane is showing")
        #expect(!m.isLegacy)
    }

    /// Only what each old tab was *currently* showing becomes a tab. Histories are dropped on purpose:
    /// resurrecting pages you had navigated away from would reopen work you had closed.
    @Test func migrated_keepsCurrentEntitiesOnly_notHistories() {
        let project = UUID(), task = UUID()
        let snap = WorkspaceSnapshot(
            tabs: [legacyTab([.page("diary"), .entity(kind: "project", id: project)], index: 1),
                   legacyTab([.entity(kind: "task", id: task), .page("tasks")], index: 1)],
            activeIndex: 0)
        let m = snap.migrated()
        #expect(m.entityTabs == [EntityTabSnapshot(kind: "project", id: project)],
                "the second tab was showing a page, so it contributes no tab")
        #expect(m.activeTabIndex == 0, "the active tab was showing the project")
    }

    @Test func migrated_dedupesTheSameEntityOpenTwice() {
        let id = UUID()
        let snap = WorkspaceSnapshot(tabs: [legacyTab([.entity(kind: "minutes", id: id)]),
                                            legacyTab([.entity(kind: "minutes", id: id)])],
                                     activeIndex: 1)
        let m = snap.migrated()
        #expect(m.entityTabs?.count == 1)
        #expect(m.activeTabIndex == 0, "the duplicate folds onto the one tab that remains")
    }

    @Test func migrated_unknownPageToken_fallsBackToDiary() {
        let snap = WorkspaceSnapshot(tabs: [legacyTab([.page("board")])], activeIndex: 0)
        #expect(snap.migrated().selectedCategory == WorkspaceCategory.tasks.rawValue)
        let odd = WorkspaceSnapshot(tabs: [legacyTab([.page("nonsense")])], activeIndex: 0)
        #expect(odd.migrated().selectedCategory == WorkspaceCategory.diary.rawValue)
    }

    @Test func migrated_isIdentityForACurrentSnapshot() {
        let snap = WorkspaceSnapshot(selectedCategory: "Tasks", entityTabs: [], activeTabIndex: nil)
        #expect(!snap.isLegacy)
        #expect(snap.migrated() == snap)
    }

    // MARK: - Coding

    @Test func snapshot_jsonRoundTrips() throws {
        let snap = WorkspaceSnapshot(
            selectedCategory: WorkspaceCategory.projects.rawValue,
            entityTabs: [EntityTabSnapshot(kind: "project", id: UUID()),
                         EntityTabSnapshot(kind: "task", id: UUID())],
            activeTabIndex: 1,
            diary: DiarySnapshot(date: FixedDates.reference, mode: "Week", tracksToday: false),
            tasksFilter: TasksFilterSnapshot(activeFilterIds: ["preset.incomplete"], searchText: "abc",
                                             sortColumnID: "urgency", sortAscending: false,
                                             dateRangeStart: nil, dateRangeEnd: nil, datePreset: "week"),
            pageFilters: ["Projects": ListFilterSnapshot(activeFilterIds: ["status.active"], searchText: "",
                                                        sortColumnID: "name", sortAscending: true)],
            boardPanelShown: true, boardFullWidth: false)
        let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self,
                                               from: try JSONEncoder().encode(snap))
        #expect(decoded == snap)
    }

    /// The real reason the legacy fields are kept: a session on disk right now is in the old shape, and a
    /// hard decode failure would silently reset the whole workspace.
    @Test func aLegacyPayloadStillDecodes() throws {
        let json = """
        {"activeIndex":0,"tabs":[{"history":[{"page":{"_0":"tasks"}}],"index":0,
        "diary":{"date":811692000,"mode":"Day","tracksToday":true},
        "tasksFilter":{"activeFilterIds":[],"searchText":"","sortColumnID":"urgency","sortAscending":false},
        "pageFilters":{}}]}
        """
        let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(json.utf8))
        #expect(decoded.isLegacy)
        #expect(decoded.migrated().selectedCategory == WorkspaceCategory.tasks.rawValue)
        #expect(decoded.migrated().boardPanelShown == nil, "absent means closed, decided at restore")
    }

    @Test func store_setGetClear() {
        let snap = WorkspaceSnapshot(selectedCategory: WorkspaceCategory.tasks.rawValue,
                                     entityTabs: [], activeTabIndex: nil)
        WorkspaceSessionStore.snapshot = snap
        #expect(WorkspaceSessionStore.snapshot == snap)
        WorkspaceSessionStore.snapshot = nil
        #expect(WorkspaceSessionStore.snapshot == nil)
    }

    // A PersistentIdentifier isn't constructible directly, so borrow one from an in-memory model.
    private func dummyID() -> PersistentIdentifier {
        let container = try! TestModelContainer.make()
        let p = Project(name: "x")
        container.mainContext.insert(p)
        return p.persistentModelID
    }
}
