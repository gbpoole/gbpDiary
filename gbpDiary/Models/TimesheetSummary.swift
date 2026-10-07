import Foundation
import SwiftData

// A cached, on-device paragraph describing one project's work over one reporting period — the prose the
// Timesheet leads each project section with. Keyed by `(nodeID, rangeStart, rangeEnd)`: the project (or the
// synthetic unattributed node) plus the exact closed, whole-day interval on screen.
//
// Purely a cache derived from the models — safe to wipe and rebuild. It is regenerated when the work it
// describes changes (`sourceFingerprint`) or the prompt version bumps, and SWEPT five weeks after it was
// last generated or shown (`touchedAt`), so a period you never look at again stops costing storage.
// All properties default so SwiftData can lightweight-migrate the store when this model is added.
@Model final class TimesheetSummary {
    @Attribute(.unique) var id: UUID = UUID()
    var nodeID: UUID = UUID()
    var rangeStart: Date = Date.distantPast
    var rangeEnd: Date = Date.distantPast
    var text: String?
    // Raw of TimesheetSummaryState: "pending" | "done" | "failed" | "unavailable".
    var summaryState: String = TimesheetSummaryState.pending.rawValue
    var summaryPromptVersion: Int = 0
    var sourceFingerprint: String = ""
    /// When this summary was last generated or shown — the eviction clock.
    var touchedAt: Date = Date()

    init(nodeID: UUID, rangeStart: Date, rangeEnd: Date) {
        self.nodeID = nodeID
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }

    var state: TimesheetSummaryState {
        get { TimesheetSummaryState(rawValue: summaryState) ?? .pending }
        set { summaryState = newValue.rawValue }
    }

    /// Does this row describe the given node + period?
    func matches(nodeID: UUID, interval: Range<Date>) -> Bool {
        self.nodeID == nodeID && rangeStart == interval.lowerBound && rangeEnd == interval.upperBound
    }
}
