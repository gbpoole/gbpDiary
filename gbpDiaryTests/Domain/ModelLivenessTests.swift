import Foundation
import SwiftData
import Testing
@testable import gbpDiary

/// Guards the fix for the SIGTRAP crash: a detail view holding a deleted model read its stored
/// properties and trapped. Detection needs BOTH signals, because each covers only half the window —
/// these tests pin that SwiftData behaviour so a regression in either is caught here rather than as a
/// crash report.
@MainActor
struct ModelLivenessTests {

    // MARK: - Pure decision

    @Test func isDead_whenFlaggedDeletedOrDetached() {
        #expect(!ModelLiveness.isDead(isDeleted: false, hasContext: true))   // ordinary live model
        #expect(ModelLiveness.isDead(isDeleted: true, hasContext: true))     // pre-save window
        #expect(ModelLiveness.isDead(isDeleted: false, hasContext: false))   // post-save window
        #expect(ModelLiveness.isDead(isDeleted: true, hasContext: false))
    }

    // MARK: - Measured SwiftData behaviour

    @Test func liveModelIsTrue_forAnInsertedModel() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)
        let m = Minutes(meetingAt: FixedDates.reference)
        ctx.insert(m)
        try ctx.save()
        #expect(!m.isDeletedOrDetached)
    }

    /// Before the save that commits the delete, `isDeleted` is the signal — the model still has a context.
    @Test func deletedBeforeSave_isDetectedByIsDeleted() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)
        let m = Minutes(meetingAt: FixedDates.reference)
        ctx.insert(m); try ctx.save()

        ctx.delete(m)
        #expect(m.isDeleted)
        #expect(m.modelContext != nil, "pre-save the model still has its context, so that signal alone is not enough")
        #expect(m.isDeletedOrDetached)
    }

    /// After that save the flag flips back to false and the context goes away — so the other signal
    /// takes over. This is the window `ModelContext.liveModel` does NOT cover.
    @Test func deletedAfterSave_isDetectedByDetachment() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)
        let m = Minutes(meetingAt: FixedDates.reference)
        ctx.insert(m); try ctx.save()
        let id = m.persistentModelID

        ctx.delete(m); try ctx.save()
        #expect(!m.isDeleted, "post-save SwiftData clears the flag")
        #expect(m.modelContext == nil)
        #expect(m.isDeletedOrDetached)
        // This assertion used to expect a non-nil result, documenting that `liveModel` only scanned
        // pending deletions and so went blind once the save cleared them. That blindness is what let a
        // stale tab chip and a mounted detail view read a deleted model and crash the app (SIGTRAP), so
        // `liveModel` now validates identity against the rows that actually exist.
        #expect(ctx.liveModel(id, as: Minutes.self) == nil,
                "a deleted-and-saved model must not resolve, or its fields get read and trap")
    }

    /// `persistentModelID` stays readable on a tombstone — it is what delete paths match on.
    @Test func persistentModelID_staysReadableAfterDeletion() throws {
        let container = try TestModelContainer.make()
        let ctx = ModelContext(container)
        let m = Minutes(meetingAt: FixedDates.reference)
        ctx.insert(m); try ctx.save()
        let id = m.persistentModelID

        ctx.delete(m); try ctx.save()
        #expect(m.persistentModelID == id)
    }
}
