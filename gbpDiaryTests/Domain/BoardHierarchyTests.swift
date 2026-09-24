import Foundation
import Testing
@testable import gbpDiary

struct BoardHierarchyTests {

    private struct T {
        let id: UUID
        var parent: UUID? = nil
        var open = true
        var plan = 0
        var tree = 0
        var name = ""
    }

    private func rows(_ members: [T], all: [T]) -> [BoardRow<T>] {
        BoardHierarchy.rows(members: members, all: all, id: \.id, parentID: \.parent,
                            planSortOrder: \.plan, treeSortOrder: \.tree)
    }

    // MARK: - What a placement touches

    @Test func placingATask_placesItsWholeOpenSubtree() {
        let root = UUID(), a = UUID(), b = UUID(), grand = UUID()
        let children = [root: [a, b], a: [grand]]
        let targets = BoardHierarchy.placementTargets(rootID: root, childrenByParent: children,
                                                      isOpen: { _ in true })
        #expect(targets == [root, a, b, grand])
    }

    @Test func placement_skipsClosedTasksAtEveryLevel() {
        let root = UUID(), open = UUID(), done = UUID()
        let children = [root: [open, done]]
        let targets = BoardHierarchy.placementTargets(rootID: root, childrenByParent: children,
                                                      isOpen: { $0 != done })
        #expect(targets == [root, open])
    }

    /// A task whose subtasks are all finished still goes on the board — as itself.
    @Test func placement_withNoOpenDescendants_placesJustTheTask() {
        let root = UUID(), done = UUID()
        let targets = BoardHierarchy.placementTargets(rootID: root, childrenByParent: [root: [done]],
                                                      isOpen: { $0 != done })
        #expect(targets == [root])
    }

    @Test func placement_isCycleSafe() {
        let a = UUID(), b = UUID()
        let targets = BoardHierarchy.placementTargets(rootID: a, childrenByParent: [a: [b], b: [a]],
                                                      isOpen: { _ in true })
        #expect(targets == [a, b])
    }

    // MARK: - Lane layout

    @Test func wholeSubtreeInALane_nestsUnderItsParent() {
        let p = T(id: UUID(), name: "parent")
        let c1 = T(id: UUID(), parent: p.id, tree: 0, name: "first")
        let c2 = T(id: UUID(), parent: p.id, tree: 1, name: "second")
        let r = rows([p, c1, c2], all: [p, c1, c2])

        #expect(r.map(\.item.name) == ["parent", "first", "second"])
        #expect(r.map(\.depth) == [0, 1, 1])
        #expect(r.allSatisfy { !$0.isContext })
    }

    /// Adding a subtask alone drags in its ancestors for context — but not its siblings.
    @Test func loneSubtask_showsAncestorsAsContext_notSiblings() {
        let p = T(id: UUID(), name: "parent")
        let chosen = T(id: UUID(), parent: p.id, tree: 0, name: "chosen")
        let sibling = T(id: UUID(), parent: p.id, tree: 1, name: "sibling")
        let r = rows([chosen], all: [p, chosen, sibling])

        #expect(r.map(\.item.name) == ["parent", "chosen"])
        #expect(r.map(\.isContext) == [true, false])
        #expect(r.map(\.depth) == [0, 1])
    }

    @Test func deepSubtask_pullsInTheWholeAncestorChain() {
        let root = T(id: UUID(), name: "root")
        let mid = T(id: UUID(), parent: root.id, name: "mid")
        let leaf = T(id: UUID(), parent: mid.id, name: "leaf")
        let r = rows([leaf], all: [root, mid, leaf])

        #expect(r.map(\.item.name) == ["root", "mid", "leaf"])
        #expect(r.map(\.isContext) == [true, true, false])
        #expect(r.map(\.depth) == [0, 1, 2])
    }

    /// Top-level groups follow board order; rows within a group follow the task tree's own order.
    @Test func groupsOrderByPlanOrder_childrenByTreeOrder() {
        let late = T(id: UUID(), plan: 5, name: "late")
        let early = T(id: UUID(), plan: 1, name: "early")
        let kidB = T(id: UUID(), parent: early.id, plan: 99, tree: 1, name: "b")
        let kidA = T(id: UUID(), parent: early.id, plan: 0, tree: 0, name: "a")
        let all = [late, early, kidB, kidA]
        let r = rows(all, all: all)

        #expect(r.map(\.item.name) == ["early", "a", "b", "late"])
    }

    /// A context row has no board order of its own, so it sorts by its earliest member.
    @Test func contextRoot_takesTheEarliestOrderOfItsMembers() {
        let other = T(id: UUID(), plan: 1, name: "other")
        let parent = T(id: UUID(), name: "parent")
        let child = T(id: UUID(), parent: parent.id, plan: 0, name: "child")
        let r = rows([other, child], all: [other, parent, child])

        #expect(r.map(\.item.name) == ["parent", "child", "other"])
    }

    @Test func noMembers_isEmpty() {
        let p = T(id: UUID(), name: "parent")
        #expect(rows([], all: [p]).isEmpty)
    }
}
