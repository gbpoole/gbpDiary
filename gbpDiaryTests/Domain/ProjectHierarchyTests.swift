import Foundation
import Testing
@testable import gbpDiary

private struct Node {
    let id = UUID()
    var parentID: UUID?
    var name: String
}

@MainActor
struct ProjectHierarchyTests {
    // Sort siblings by name for deterministic order.
    private func rows(_ nodes: [Node], matched: Set<UUID>) -> [HierarchyRow<Node>] {
        ProjectHierarchy.rows(all: nodes, id: { $0.id }, parentID: { $0.parentID },
                              matched: matched, sortSiblings: { $0.sorted { $0.name < $1.name } })
    }

    @Test func flat_allDepthZeroInSortOrder() {
        let b = Node(parentID: nil, name: "b")
        let a = Node(parentID: nil, name: "a")
        let r = rows([b, a], matched: [a.id, b.id])
        #expect(r.map(\.item.name) == ["a", "b"])
        #expect(r.allSatisfy { $0.depth == 0 && $0.isMatch })
    }

    @Test func threeLevelCascade_nestsDepths() {
        let root = Node(parentID: nil, name: "root")
        let mid = Node(parentID: root.id, name: "mid")
        let leaf = Node(parentID: mid.id, name: "leaf")
        let r = rows([leaf, mid, root], matched: [root.id, mid.id, leaf.id])
        #expect(r.map(\.item.name) == ["root", "mid", "leaf"])
        #expect(r.map(\.depth) == [0, 1, 2])
    }

    @Test func siblings_orderedByComparator_underParent() {
        let root = Node(parentID: nil, name: "root")
        let z = Node(parentID: root.id, name: "z")
        let a = Node(parentID: root.id, name: "a")
        let r = rows([z, a, root], matched: [root.id, z.id, a.id])
        #expect(r.map(\.item.name) == ["root", "a", "z"])
        #expect(r.map(\.depth) == [0, 1, 1])
    }

    @Test func filteringDeepMatch_keepsAncestorsAsContext_excludesUnrelated() {
        let root = Node(parentID: nil, name: "root")
        let mid = Node(parentID: root.id, name: "mid")
        let leaf = Node(parentID: mid.id, name: "leaf")
        let unrelated = Node(parentID: root.id, name: "other")   // sibling of mid, not on the match path
        let r = rows([root, mid, leaf, unrelated], matched: [leaf.id])

        #expect(r.map(\.item.name) == ["root", "mid", "leaf"])   // ancestors kept, unrelated dropped
        #expect(r.first { $0.item.name == "leaf" }?.isMatch == true)
        #expect(r.first { $0.item.name == "root" }?.isMatch == false)   // context only
        #expect(r.first { $0.item.name == "mid" }?.isMatch == false)
        #expect(!r.contains { $0.item.name == "other" })
    }

    @Test func noMatches_isEmpty() {
        let a = Node(parentID: nil, name: "a")
        #expect(rows([a], matched: []).isEmpty)
    }

    @Test func cycle_terminates() {
        var a = Node(parentID: nil, name: "a")
        var b = Node(parentID: nil, name: "b")
        a.parentID = b.id
        b.parentID = a.id   // a↔b cycle
        let r = rows([a, b], matched: [a.id, b.id])
        #expect(r.count <= 2)   // no infinite loop; each emitted at most once
    }

    @Test func orphanParent_treatedAsRoot() {
        let child = Node(parentID: UUID(), name: "child")   // parent id not in the set
        let r = rows([child], matched: [child.id])
        #expect(r.count == 1)
        #expect(r[0].depth == 0)
    }
}
