import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct TaskBreakdownTests {

    @Test func createsNestedSubtreeInOutlineOrder() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let parent = Task(summary: "Ship release")
        context.insert(parent)

        let roots = TaskBreakdown.create(text: """
            Write changelog
                Collect PRs
                Draft copy
            Tag the build
            """, under: parent, in: context)
        try context.save()

        #expect(roots.map(\.summary) == ["Write changelog", "Tag the build"])
        #expect(roots.map(\.sortOrder) == [0, 1])

        let changelog = try #require(roots.first)
        #expect(changelog.parent?.id == parent.id)
        let grandchildren = changelog.children.sorted { $0.sortOrder < $1.sortOrder }
        #expect(grandchildren.map(\.summary) == ["Collect PRs", "Draft copy"])
        #expect(grandchildren.map(\.sortOrder) == [0, 1])
    }

    @Test func inheritsProjectAndAssigneeFromParent() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let project = Project(name: "Apollo")
        let person = Person(name: "Ada")
        let parent = Task(summary: "Ship release")
        context.insert(project); context.insert(person); context.insert(parent)
        parent.project = project
        parent.assignee = person

        let roots = TaskBreakdown.create(text: "Write changelog", under: parent, in: context)
        try context.save()

        let child = try #require(roots.first)
        #expect(child.project?.id == project.id)
        #expect(child.assignee?.id == person.id)
    }

    @Test func explicitProjectOverridesInheritance() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let inherited = Project(name: "Apollo")
        let override = Project(name: "Gemini")
        let parent = Task(summary: "Ship release")
        context.insert(inherited); context.insert(override); context.insert(parent)
        parent.project = inherited

        let roots = TaskBreakdown.create(text: "Write changelog", under: parent,
                                         project: override, in: context)
        try context.save()

        #expect(try #require(roots.first).project?.id == override.id)
    }

    /// A reviewed parent yields reviewed subtasks, so a breakdown doesn't vanish from the Reviewed
    /// table (which hides open tasks still flagged for triage).
    @Test func subtasksInheritParentTriageState() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let reviewed = Task(summary: "Reviewed parent")
        let untriaged = Task(summary: "Fresh parent")
        context.insert(reviewed); context.insert(untriaged)
        reviewed.markReviewed()

        let fromReviewed = TaskBreakdown.create(text: "child", under: reviewed, in: context)
        let fromUntriaged = TaskBreakdown.create(text: "child", under: untriaged, in: context)
        try context.save()

        #expect(try #require(fromReviewed.first).needsTriage == false)
        #expect(try #require(fromUntriaged.first).needsTriage == true)
    }

    /// Typed with no parent it is fresh capture, so it stays in the Inbox.
    @Test func rootLevelBreakdownStaysUntriaged() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let roots = TaskBreakdown.create(text: "Something new", under: nil, in: context)
        try context.save()
        #expect(try #require(roots.first).needsTriage == true)
    }

    @Test func appendsAfterExistingChildrenWithoutReshuffling() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let parent = Task(summary: "Ship release")
        let existing = Task(summary: "Already here")
        context.insert(parent); context.insert(existing)
        existing.parent = parent
        existing.sortOrder = 7

        let roots = TaskBreakdown.create(text: "New one", under: parent, in: context)
        try context.save()

        #expect(existing.sortOrder == 7)
        #expect(try #require(roots.first).sortOrder == 8)
    }

    @Test func emptyOrWhitespaceTextCreatesNothing() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let parent = Task(summary: "Ship release")
        context.insert(parent)

        #expect(TaskBreakdown.create(text: "   \n\n  ", under: parent, in: context).isEmpty)
        #expect(parent.children.isEmpty)
    }
}
