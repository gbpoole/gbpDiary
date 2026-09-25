import Foundation
import Testing
@testable import gbpDiary

struct TaskParentingTests {

    @Test func subtree_includesSelfAndAllDescendants() {
        let root = UUID(), a = UUID(), b = UUID(), grand = UUID(), unrelated = UUID()
        let children = [root: [a, b], a: [grand], unrelated: [UUID()]]
        #expect(TaskParenting.subtree(of: root, childrenByParent: children) == [root, a, b, grand])
    }

    @Test func subtree_ofALeaf_isJustItself() {
        let leaf = UUID()
        #expect(TaskParenting.subtree(of: leaf, childrenByParent: [:]) == [leaf])
    }

    @Test func cannotParentATaskToItself() {
        let a = UUID()
        #expect(TaskParenting.wouldCreateCycle(taskID: a, newParentID: a, childrenByParent: [:]))
    }

    @Test func cannotParentATaskToItsOwnChild() {
        let parent = UUID(), child = UUID()
        #expect(TaskParenting.wouldCreateCycle(taskID: parent, newParentID: child,
                                               childrenByParent: [parent: [child]]))
    }

    /// The case a naive "is it my direct child?" check misses.
    @Test func cannotParentATaskToADeepDescendant() {
        let root = UUID(), mid = UUID(), leaf = UUID()
        let children = [root: [mid], mid: [leaf]]
        #expect(TaskParenting.wouldCreateCycle(taskID: root, newParentID: leaf,
                                               childrenByParent: children))
    }

    @Test func parentingToAnUnrelatedTaskIsFine() {
        let a = UUID(), b = UUID(), childOfA = UUID()
        #expect(!TaskParenting.wouldCreateCycle(taskID: a, newParentID: b,
                                                childrenByParent: [a: [childOfA]]))
    }

    /// Parenting a task UP to its own ancestor is legal — it is already beneath it.
    @Test func parentingToAnAncestorIsAllowed() {
        let root = UUID(), mid = UUID(), leaf = UUID()
        let children = [root: [mid], mid: [leaf]]
        #expect(!TaskParenting.wouldCreateCycle(taskID: leaf, newParentID: root,
                                                childrenByParent: children))
    }

    @Test func existingCycleInTheDataTerminates() {
        let a = UUID(), b = UUID()
        #expect(TaskParenting.subtree(of: a, childrenByParent: [a: [b], b: [a]]) == [a, b])
    }
}
