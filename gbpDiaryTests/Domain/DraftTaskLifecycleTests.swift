import Foundation
import SwiftData
import Testing
@testable import gbpDiary

/// **SPIKE.** The row-based subtask editor wants one component in two modes, where a buffered (not yet
/// saved) row is an *un-inserted* `@Model Task` — so the live and buffered modes render the same row type.
///
/// That bets on SwiftData behaving for a model that has never met a `ModelContext`. This app has already
/// been bitten twice by SwiftData lifecycle assumptions (the tombstone SIGTRAPs), so the bet is measured
/// here before anything is built on it. Each test pins one fact the design depends on; the fallback if a
/// load-bearing one fails is a `SubtaskRow` enum (`.task(Task)` / `.draft(DraftRow)`).
@MainActor
struct DraftTaskLifecycleTests {

    // MARK: - Can a draft exist at all?

    /// Baseline: a `@Model` is just a class until inserted, so stored properties are readable and writable.
    @Test func uninsertedTask_readsAndWritesItsOwnProperties() {
        let draft = Task(summary: "draft row")
        #expect(draft.summary == "draft row")
        draft.summary = "edited"
        #expect(draft.summary == "edited")
        #expect(draft.status == .todo)
        #expect(draft.needsTriage, "a fresh task is inbox-bound until reviewed")
    }

    /// A draft has no context. **This is the dangerous finding for the design:** every detail view guards
    /// its body on `isDeletedOrDetached`, which is true whenever `modelContext == nil` — so a draft row
    /// looks exactly like a deleted tombstone to that guard.
    @Test func uninsertedTask_hasNoContext_soItLooksDetached() {
        let draft = Task(summary: "draft row")
        #expect(draft.modelContext == nil)
        #expect(!draft.isDeleted)
        #expect(draft.isDeletedOrDetached,
                "a draft is indistinguishable from a post-save-deleted model by this signal")
    }

    // MARK: - Relationships between two drafts (Tab/Shift-Tab depth changes)

    /// Tab sets `parent` on a draft. Does the inverse (`children`) materialise without a context?
    @Test func uninsertedTasks_parentAssignment_populatesTheInverse() {
        let parent = Task(summary: "parent")
        let child = Task(summary: "child")
        child.parent = parent
        #expect(child.parent?.summary == "parent")
        #expect(parent.children.map(\.summary) == ["child"],
                "the design's depth changes rely on the inverse being maintained off-context")
    }

    /// Shift-Tab clears a parent, and the editor reads `children` to lay the tree out.
    @Test func uninsertedTasks_clearingParent_updatesTheInverse() {
        let parent = Task(summary: "parent")
        let child = Task(summary: "child")
        child.parent = parent
        child.parent = nil
        #expect(child.parent == nil)
        #expect(parent.children.isEmpty)
    }

    // MARK: - Observation (the row's TextField binds through @Bindable)

    /// A row edits its summary through `@Bindable var task: Task`, which is `@Observable` under the hood.
    /// If mutations on an un-inserted model don't notify observers, typing in a draft row won't redraw —
    /// which would sink the shared-component design on its own.
    @Test func uninsertedTask_mutation_notifiesObservers() {
        let draft = Task(summary: "before")
        var observed = false
        withObservationTracking {
            _ = draft.summary
        } onChange: {
            observed = true
        }
        draft.summary = "after"
        #expect(observed, "a draft row must redraw as you type into it")
    }

    /// The tree is laid out from `children`, so a depth change must notify too.
    @Test func uninsertedTask_relationshipChange_notifiesObservers() {
        let parent = Task(summary: "parent")
        let child = Task(summary: "child")
        var observed = false
        withObservationTracking {
            _ = parent.children
        } onChange: {
            observed = true
        }
        child.parent = parent
        #expect(observed, "Tab must redraw the tree it just restructured")
    }

    // MARK: - Identity

    /// `persistentModelID` is what `focusOrOpen(.task(...))` and the deleted-model guards are keyed on.
    /// A draft has no store row, so reading it may be meaningless — or may trap. Measured, because the
    /// shared row code paths touch it.
    @Test func uninsertedTask_persistentModelIDIsReadable() {
        let draft = Task(summary: "draft")
        let id = draft.persistentModelID
        #expect(String(describing: id).isEmpty == false)
    }

    /// `Identifiable` for the rows is the app's own `@Attribute(.unique) var id: UUID`, not the SwiftData
    /// id — so a draft already has a stable, usable identity for `ForEach`.
    @Test func uninsertedTask_hasAStableAppLevelUUID() {
        let draft = Task(summary: "draft")
        let first = draft.id
        draft.summary = "edited"
        #expect(draft.id == first)
        #expect(draft.id != Task(summary: "other").id)
    }

    // MARK: - Commit (what `TaskEditorSheet.save()` would do)

    /// The buffered mode commits by inserting. If inserting the root pulls its draft subtree in through
    /// the relationship, commit is one call; if not, every node must be inserted explicitly.
    @Test func insertingTheRoot_tellsUsWhetherDraftChildrenFollow() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let root = Task(summary: "root")
        let child = Task(summary: "child")
        child.parent = root
        context.insert(root)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Task>())
        #expect(all.contains { $0.summary == "root" })
        #expect(all.contains { $0.summary == "child" },
                "if this fails, commit must insert every draft node explicitly")
        #expect(root.modelContext != nil)
        #expect(child.modelContext != nil, "and the child must gain a context to be editable after commit")
    }

    /// After commit the former draft must behave like any other task — including passing the liveness
    /// guard that it failed as a draft.
    @Test func afterInsert_theDraftIsNoLongerDetached() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let draft = Task(summary: "draft")

        #expect(draft.isDeletedOrDetached)
        context.insert(draft)
        try context.save()

        #expect(!draft.isDeletedOrDetached)
        #expect(draft.modelContext != nil)
    }
}
