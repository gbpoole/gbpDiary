import Foundation
import Testing
@testable import gbpDiary

struct CurationWalkTests {
    private struct P {
        let id: UUID
        let parent: UUID?
        let name: String
        let active: Bool
    }

    private func walk(_ all: [P], root: UUID) -> [String] {
        CurationWalk.order(
            rootID: root,
            all: all,
            id: { $0.id },
            parentID: { $0.parent },
            isActive: { $0.active },
            sortSiblings: { $0.sorted { $0.name < $1.name } }
        ).map(\.name)
    }

    @Test func rootThenActiveSubprojects_depthFirst() {
        let root = UUID(); let a = UUID(); let b = UUID(); let a1 = UUID()
        let all = [
            P(id: root, parent: nil, name: "root", active: true),
            P(id: a, parent: root, name: "a", active: true),
            P(id: a1, parent: a, name: "a1", active: true),
            P(id: b, parent: root, name: "b", active: true),
        ]
        #expect(walk(all, root: root) == ["root", "a", "a1", "b"])
    }

    @Test func completedSubprojectAndSubtreePruned() {
        let root = UUID(); let a = UUID(); let a1 = UUID(); let b = UUID()
        let all = [
            P(id: root, parent: nil, name: "root", active: true),
            P(id: a, parent: root, name: "a", active: false),   // completed → pruned with a1
            P(id: a1, parent: a, name: "a1", active: true),
            P(id: b, parent: root, name: "b", active: true),
        ]
        #expect(walk(all, root: root) == ["root", "b"])
    }

    @Test func rootIncludedEvenIfCompleted() {
        let root = UUID()
        let all = [P(id: root, parent: nil, name: "root", active: false)]
        #expect(walk(all, root: root) == ["root"])
    }

    @Test func siblingsOrderedByComparator() {
        let root = UUID(); let z = UUID(); let a = UUID()
        let all = [
            P(id: root, parent: nil, name: "root", active: true),
            P(id: z, parent: root, name: "z", active: true),
            P(id: a, parent: root, name: "a", active: true),
        ]
        #expect(walk(all, root: root) == ["root", "a", "z"])
    }

    @Test func unknownRoot_isEmpty() {
        #expect(walk([], root: UUID()).isEmpty)
    }

    @Test func cycleTerminates() {
        let x = UUID(); let y = UUID()
        let all = [
            P(id: x, parent: y, name: "x", active: true),
            P(id: y, parent: x, name: "y", active: true),
        ]
        // Starting at x: emits x, then its active child y, whose child x is already visited → stops.
        #expect(walk(all, root: x) == ["x", "y"])
    }
}
