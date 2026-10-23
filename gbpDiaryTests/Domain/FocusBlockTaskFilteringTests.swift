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

    // MARK: - Project filter chips
    //
    // The editor has no project field: a block is backed by a task and takes that task's project, so
    // narrowing by project is a filter on the task picker. The view builds the chip ids and reads them
    // back, so the format lives here — two spellings would stop matching without failing anything.

    @Test func projectFilterID_isStableForTheSameProject() {
        let id = UUID()
        #expect(FocusBlockTaskFiltering.projectFilterID(id) == FocusBlockTaskFiltering.projectFilterID(id))
        #expect(FocusBlockTaskFiltering.projectFilterID(id) != FocusBlockTaskFiltering.projectFilterID(UUID()))
    }

    @Test func soleProjectID_isTheOneBeingFilteredTo() {
        let a = UUID(), b = UUID()
        let active: Set<String> = [FocusBlockTaskFiltering.projectFilterID(b)]
        #expect(FocusBlockTaskFiltering.soleProjectID(activeFilterIDs: active, among: [a, b]) == b)
    }

    /// No filter means nothing to infer — a new task must be given a project explicitly.
    @Test func soleProjectID_isNilWhenNothingIsFiltered() {
        #expect(FocusBlockTaskFiltering.soleProjectID(activeFilterIDs: [], among: [UUID()]) == nil)
    }

    /// Several filters give no reason to prefer one, so the editor asks rather than guessing.
    @Test func soleProjectID_isNilWhenSeveralProjectsAreFiltered() {
        let a = UUID(), b = UUID()
        let active: Set<String> = [FocusBlockTaskFiltering.projectFilterID(a),
                                   FocusBlockTaskFiltering.projectFilterID(b)]
        #expect(FocusBlockTaskFiltering.soleProjectID(activeFilterIDs: active, among: [a, b]) == nil)
    }

    /// A filter for a project that is no longer offered (completed, or deleted) resolves to nothing
    /// rather than to the wrong project.
    @Test func soleProjectID_isNilWhenTheFilteredProjectIsNotOffered() {
        let active: Set<String> = [FocusBlockTaskFiltering.projectFilterID(UUID())]
        #expect(FocusBlockTaskFiltering.soleProjectID(activeFilterIDs: active, among: [UUID()]) == nil)
    }

    @Test func soleProjectID_ignoresAnUnrelatedFilterId() {
        #expect(FocusBlockTaskFiltering.soleProjectID(activeFilterIDs: ["status.open"], among: [UUID()]) == nil)
    }
}
