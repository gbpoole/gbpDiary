import Testing
import Foundation
@testable import gbpDiary

@Suite("FocusBlockTaskFiltering")
struct FocusBlockTaskFilteringTests {
    private struct Row {
        let active: Bool
        let project: UUID?
    }

    private func filter(_ rows: [Row], _ active: Set<UUID>) -> [Row] {
        FocusBlockTaskFiltering.filter(rows, isActive: { $0.active }, projectID: { $0.project },
                                       activeProjectIDs: active)
    }

    @Test func emptySelection_returnsAllActiveTasks() {
        let p = UUID()
        let rows = [Row(active: true, project: p), Row(active: true, project: nil)]
        #expect(filter(rows, []).count == 2)
    }

    @Test func inactiveTasks_alwaysExcluded() {
        let p = UUID()
        let rows = [Row(active: false, project: p), Row(active: true, project: p)]
        #expect(filter(rows, []).count == 1)
        #expect(filter(rows, [p]).count == 1)
    }

    @Test func singleProject_keepsOnlyThatProject() {
        let a = UUID(); let b = UUID()
        let rows = [Row(active: true, project: a), Row(active: true, project: b)]
        let result = filter(rows, [a])
        #expect(result.count == 1)
        #expect(result.first?.project == a)
    }

    @Test func multipleProjects_areOred() {
        let a = UUID(); let b = UUID(); let c = UUID()
        let rows = [Row(active: true, project: a), Row(active: true, project: b), Row(active: true, project: c)]
        #expect(filter(rows, [a, b]).count == 2)
    }

    @Test func projectlessTask_excludedWhenFilterActive() {
        let a = UUID()
        let rows = [Row(active: true, project: nil), Row(active: true, project: a)]
        let result = filter(rows, [a])
        #expect(result.count == 1)
        #expect(result.first?.project == a)
    }
}
