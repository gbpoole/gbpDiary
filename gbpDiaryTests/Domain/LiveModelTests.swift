import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct LiveModelTests {
    @Test func liveModel_returnsModelWhenPresent() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let m = Minutes(meetingAt: FixedDates.reference); m.summary = "Standup"
        ctx.insert(m)
        let id = m.persistentModelID

        let resolved = ctx.liveModel(id, as: Minutes.self)
        #expect(resolved != nil)
        #expect(resolved?.summary == "Standup")   // reading a stored property is safe while live
    }

    // THE regression: the app crashed twice (SIGTRAP) reading a deleted model AFTER its delete was saved.
    // `deletedModelsArray` is cleared by the save, `isDeleted` goes back to false and the model keeps its
    // context — so every in-memory signal says "alive" while reading any stored property traps. Only
    // identity survives, which is what `isLive` compares.
    @Test func isLive_isFalseAfterTheDeleteIsSaved() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let task = Task(summary: "doomed")
        ctx.insert(task)
        try ctx.save()
        let id = task.persistentModelID
        #expect(ctx.isLive(id, as: Task.self))

        ctx.delete(task)
        try ctx.save()                       // the window the old check missed

        #expect(!ctx.isLive(id, as: Task.self))
        #expect(ctx.liveModel(id, as: Task.self) == nil)
    }

    @Test func isLive_isTrueForAnInsertedButUnsavedModel() throws {
        // A brand-new meeting being filled in isn't on disk yet, but it is perfectly alive — treating it
        // as dead would replace the editor with a placeholder the moment it was created.
        let ctx = ModelContext(try TestModelContainer.make())
        let m = Minutes(meetingAt: FixedDates.reference)
        ctx.insert(m)
        #expect(ctx.isLive(m.persistentModelID, as: Minutes.self))
        #expect(ctx.liveModel(m.persistentModelID, as: Minutes.self) != nil)
    }

    @Test func isMissing_coversBothWindowsForAHeldModel() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let m = Minutes(meetingAt: FixedDates.reference)
        ctx.insert(m)
        try ctx.save()
        #expect(!m.isMissing(in: ctx))

        ctx.delete(m)
        #expect(m.isMissing(in: ctx))        // before the save
        try ctx.save()
        #expect(m.isMissing(in: ctx))        // and after it — the window that crashed
    }

    @Test func liveModel_returnsNilAfterDelete() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let m = Minutes(meetingAt: FixedDates.reference); m.summary = "Standup"
        ctx.insert(m)
        let id = m.persistentModelID

        ctx.delete(m)   // deleted this session, not yet saved — the crash window
        // The guard must exclude it: we must NOT read `.summary` off the deleted instance (that traps).
        #expect(ctx.liveModel(id, as: Minutes.self) == nil)
    }

    @Test func liveModel_wrongType_returnsNil() throws {
        let ctx = ModelContext(try TestModelContainer.make())
        let m = Minutes(meetingAt: FixedDates.reference)
        ctx.insert(m)
        #expect(ctx.liveModel(m.persistentModelID, as: Project.self) == nil)
    }
}
