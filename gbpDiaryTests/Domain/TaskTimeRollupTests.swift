import Foundation
import Testing
@testable import gbpDiary

struct TaskTimeRollupTests {
    @Test func leaf_isJustOwnHours() {
        let a = UUID()
        #expect(TaskTimeRollup.subtreeHours(rootID: a, ownHours: [a: 2.5], childrenByParent: [:]) == 2.5)
    }

    @Test func leaf_withNoLoggedHours_isZero() {
        let a = UUID()
        #expect(TaskTimeRollup.subtreeHours(rootID: a, ownHours: [:], childrenByParent: [:]) == 0)
    }

    @Test func parent_sumsOwnPlusDescendants() {
        let root = UUID(); let c1 = UUID(); let c2 = UUID(); let g = UUID()
        let own: [UUID: Double] = [root: 1, c1: 2, c2: 3, g: 4]
        let kids: [UUID: [UUID]] = [root: [c1, c2], c1: [g]]
        // 1 + (2 + 4) + 3 = 10
        #expect(TaskTimeRollup.subtreeHours(rootID: root, ownHours: own, childrenByParent: kids) == 10)
    }

    @Test func subtreeOfChild_excludesSiblings() {
        let root = UUID(); let c1 = UUID(); let c2 = UUID()
        let own: [UUID: Double] = [root: 1, c1: 2, c2: 3]
        let kids: [UUID: [UUID]] = [root: [c1, c2]]
        #expect(TaskTimeRollup.subtreeHours(rootID: c1, ownHours: own, childrenByParent: kids) == 2)
    }

    @Test func cycle_countsEachNodeOnce() {
        let a = UUID(); let b = UUID()
        let own: [UUID: Double] = [a: 1, b: 2]
        let kids: [UUID: [UUID]] = [a: [b], b: [a]]   // cycle
        #expect(TaskTimeRollup.subtreeHours(rootID: a, ownHours: own, childrenByParent: kids) == 3)
    }
}
