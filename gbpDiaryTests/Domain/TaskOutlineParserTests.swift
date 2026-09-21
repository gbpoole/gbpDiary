import Foundation
import Testing
@testable import gbpDiary

struct TaskOutlineParserTests {
    @Test func flatLines_becomeRoots() {
        let nodes = TaskOutlineParser.parse("First\nSecond\nThird")
        #expect(nodes == [OutlineNode(summary: "First"),
                          OutlineNode(summary: "Second"),
                          OutlineNode(summary: "Third")])
    }

    @Test func indentationNestsChildren() {
        let text = "Parent\n    Child A\n    Child B"
        let nodes = TaskOutlineParser.parse(text)
        #expect(nodes == [OutlineNode(summary: "Parent", children: [
            OutlineNode(summary: "Child A"),
            OutlineNode(summary: "Child B"),
        ])])
    }

    @Test func tabsCountAsOneLevel() {
        let text = "Parent\n\tChild\n\t\tGrandchild"
        let nodes = TaskOutlineParser.parse(text)
        #expect(nodes == [OutlineNode(summary: "Parent", children: [
            OutlineNode(summary: "Child", children: [OutlineNode(summary: "Grandchild")]),
        ])])
    }

    @Test func listMarkersAreStripped() {
        let text = "- Parent\n    - Child\n    * Other\n    + Plus"
        let nodes = TaskOutlineParser.parse(text)
        #expect(nodes == [OutlineNode(summary: "Parent", children: [
            OutlineNode(summary: "Child"),
            OutlineNode(summary: "Other"),
            OutlineNode(summary: "Plus"),
        ])])
    }

    @Test func blankLinesIgnored() {
        let text = "A\n\n   \nB"
        #expect(TaskOutlineParser.parse(text) == [OutlineNode(summary: "A"), OutlineNode(summary: "B")])
    }

    @Test func overIndentJumpClampsToParentPlusOne() {
        // Second line jumps two levels deep; it should still nest as a direct child, not be lost.
        let text = "Parent\n        Child"   // 8 spaces = depth 2 with width 4
        let nodes = TaskOutlineParser.parse(text)
        #expect(nodes == [OutlineNode(summary: "Parent", children: [OutlineNode(summary: "Child")])])
    }

    @Test func firstLineIndented_isStillARoot() {
        let text = "        Deep first line"
        #expect(TaskOutlineParser.parse(text) == [OutlineNode(summary: "Deep first line")])
    }

    @Test func emptyText_isEmpty() {
        #expect(TaskOutlineParser.parse("").isEmpty)
        #expect(TaskOutlineParser.parse("   \n  ").isEmpty)
    }

    @Test func outdentReturnsToAncestor() {
        let text = "A\n    A1\n        A1a\n    A2\nB"
        let nodes = TaskOutlineParser.parse(text)
        #expect(nodes == [
            OutlineNode(summary: "A", children: [
                OutlineNode(summary: "A1", children: [OutlineNode(summary: "A1a")]),
                OutlineNode(summary: "A2"),
            ]),
            OutlineNode(summary: "B"),
        ])
    }

    @Test func bareHyphenWithNoText_isIgnored() {
        // A lone "- " has no summary → dropped rather than creating an empty task.
        #expect(TaskOutlineParser.parse("- \nReal").map(\.summary) == ["Real"])
    }
}
