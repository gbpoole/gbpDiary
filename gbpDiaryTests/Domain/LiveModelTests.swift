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
