import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct WorkspaceSessionTests {
    @Test func categoryTokens_roundTrip() {
        let tabs: [WorkspaceTab] = [.diary, .chat, .tasks, .projects, .people, .institutions, .meetings,
                                    .documents, .images, .tags, .timesheet, .content]
        for tab in tabs {
            let token = WorkspaceTabCoding.token(forCategoryTab: tab)
            #expect(token != nil)
            #expect(WorkspaceTabCoding.categoryTab(forToken: token!) == tab)
        }
        #expect(WorkspaceTabCoding.token(forCategoryTab: .chat) == "chat")
    }

    @Test func categoryToken_nilForUnknownToken() {
        #expect(WorkspaceTabCoding.categoryTab(forToken: "nonsense") == nil)
    }

    @Test func entityKind_tokens() {
        // Category tabs have no entity kind; entity tabs have a stable kind token and no page token.
        #expect(WorkspaceTabCoding.entityKind(for: .diary) == nil)
        let projectTab = WorkspaceTab.project(dummyID())
        #expect(WorkspaceTabCoding.entityKind(for: projectTab) == "project")
        #expect(WorkspaceTabCoding.token(forCategoryTab: projectTab) == nil)
    }

    @Test func snapshot_jsonRoundTrips() throws {
        let snap = WorkspaceSnapshot(
            tabs: [
                TabSnapshot(
                    history: [.page("diary"), .entity(kind: "project", id: UUID())],
                    index: 1,
                    diary: DiarySnapshot(date: FixedDates.reference, mode: "Week", tracksToday: false),
                    tasksFilter: TasksFilterSnapshot(activeFilterIds: ["preset.incomplete"], searchText: "abc",
                                                     sortColumnID: "urgency", sortAscending: false,
                                                     dateRangeStart: nil, dateRangeEnd: nil, datePreset: "week"),
                    pageFilters: ["Projects": ListFilterSnapshot(activeFilterIds: ["status.active"],
                                                                 searchText: "", sortColumnID: "name", sortAscending: true)])
            ],
            activeIndex: 0)
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
        #expect(decoded == snap)
    }

    @Test func store_setGetClear() {
        let snap = WorkspaceSnapshot(tabs: [
            TabSnapshot(history: [.page("tasks")], index: 0,
                        diary: DiarySnapshot(date: FixedDates.reference, mode: "Day", tracksToday: true),
                        tasksFilter: TasksFilterSnapshot(activeFilterIds: [], searchText: "", sortColumnID: "urgency",
                                                         sortAscending: false, dateRangeStart: nil, dateRangeEnd: nil, datePreset: nil),
                        pageFilters: [:])
        ], activeIndex: 0)
        WorkspaceSessionStore.snapshot = snap
        #expect(WorkspaceSessionStore.snapshot == snap)
        WorkspaceSessionStore.snapshot = nil
        #expect(WorkspaceSessionStore.snapshot == nil)
    }

    // A throwaway PersistentIdentifier isn't constructible directly; category-token nil check above
    // exercises the entity branch without needing a live model. This helper builds one via a fresh model.
    private func dummyID() -> PersistentIdentifier {
        // Uses an in-memory model only to obtain a PersistentIdentifier value for the mapping check.
        let container = try! TestModelContainer.make()
        let p = Project(name: "x")
        container.mainContext.insert(p)
        return p.persistentModelID
    }
}
