import XCTest
@testable import gbpDiary

/// The Tasks table lays its rows out as a parent → child task tree via the generic, pure
/// `ProjectHierarchy.rows` (shared with Projects rather than reimplemented). These cases pin the
/// task-shaped expectations: a matching subtask drags its ancestors in as dimmed context, a
/// non-matching subtree stays hidden, and siblings honour the table's sort comparator.
final class TaskHierarchyTests: XCTestCase {

    /// Stand-in for `TaskRow` — the helper is generic, so the tests need only id/parent/sort key.
    private struct Row: Equatable {
        let id: UUID
        let parentID: UUID?
        let summaryKey: String
    }

    private func rows(_ all: [Row], matched: Set<UUID>) -> [HierarchyRow<Row>] {
        ProjectHierarchy.rows(all: all, id: \.id, parentID: \.parentID, matched: matched,
                              sortSiblings: { $0.sorted { $0.summaryKey < $1.summaryKey } })
    }

    func testMatchingSubtask_keepsAncestorsAsDimmedContext() {
        let parent = Row(id: UUID(), parentID: nil, summaryKey: "ship release")
        let child = Row(id: UUID(), parentID: parent.id, summaryKey: "write changelog")

        // Only the child matches (e.g. the parent is completed and filtered out).
        let result = rows([parent, child], matched: [child.id])

        XCTAssertEqual(result.map(\.item), [parent, child])
        XCTAssertEqual(result.map(\.depth), [0, 1])
        // The parent is context only — the view dims it so the real match stands out.
        XCTAssertEqual(result.map(\.isMatch), [false, true])
    }

    func testMatchingParent_doesNotRevealNonMatchingSubtasks() {
        let parent = Row(id: UUID(), parentID: nil, summaryKey: "ship release")
        let child = Row(id: UUID(), parentID: parent.id, summaryKey: "write changelog")

        let result = rows([parent, child], matched: [parent.id])

        XCTAssertEqual(result.map(\.item), [parent])
        XCTAssertEqual(result.map(\.isMatch), [true])
    }

    func testSiblings_orderedByComparatorUnderTheirParent() {
        let parent = Row(id: UUID(), parentID: nil, summaryKey: "a parent")
        let zeta = Row(id: UUID(), parentID: parent.id, summaryKey: "zeta")
        let alpha = Row(id: UUID(), parentID: parent.id, summaryKey: "alpha")

        let result = rows([parent, zeta, alpha], matched: [parent.id, zeta.id, alpha.id])

        XCTAssertEqual(result.map(\.item), [parent, alpha, zeta])
        XCTAssertEqual(result.map(\.depth), [0, 1, 1])
    }

    func testDeepSubtaskMatch_keepsWholeAncestorChain() {
        let root = Row(id: UUID(), parentID: nil, summaryKey: "root")
        let mid = Row(id: UUID(), parentID: root.id, summaryKey: "mid")
        let leaf = Row(id: UUID(), parentID: mid.id, summaryKey: "leaf")
        let unrelated = Row(id: UUID(), parentID: nil, summaryKey: "unrelated")

        let result = rows([root, mid, leaf, unrelated], matched: [leaf.id])

        XCTAssertEqual(result.map(\.item), [root, mid, leaf])
        XCTAssertEqual(result.map(\.depth), [0, 1, 2])
        XCTAssertEqual(result.map(\.isMatch), [false, false, true])
    }

    func testNoMatches_isEmpty() {
        let parent = Row(id: UUID(), parentID: nil, summaryKey: "ship release")
        XCTAssertTrue(rows([parent], matched: []).isEmpty)
    }
}
