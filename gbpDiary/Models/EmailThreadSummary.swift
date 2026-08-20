import Foundation
import SwiftData

// A cached, on-device synthesized summary of one email conversation for one day — the whole-thread day
// summary shown on the diary Email row and in the activity email digest. Keyed by `threadKey` (normalized
// subject + other party, see EmailThreading) + `dayStart`. Regenerated when the thread's membership or any
// member's per-email summary changes (via `sourceFingerprint`) or the prompt version bumps. Purely a cache
// derived from EmailMessages — safe to wipe and rebuild. All properties default so SwiftData can
// lightweight-migrate the store when this model is added.
@Model final class EmailThreadSummary {
    @Attribute(.unique) var id: UUID = UUID()
    var threadKey: String = ""
    var dayStart: Date = Date.distantPast
    var text: String?
    // Raw of EmailSummaryState: "pending" | "done" | "failed" | "unavailable".
    var summaryState: String = EmailSummaryState.pending.rawValue
    var summaryPromptVersion: Int = 0
    var sourceFingerprint: String = ""

    init(threadKey: String, dayStart: Date) {
        self.threadKey = threadKey
        self.dayStart = dayStart
    }
}
