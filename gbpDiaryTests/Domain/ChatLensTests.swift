import Foundation
import Testing
@testable import gbpDiary

struct ChatLensTests {
    private func scope(totals: Bool = false, interval: Bool = false) -> ChatQueryScope {
        var s = ChatQueryScope()
        s.wantsTimeTotals = totals
        if interval { s.interval = Date()..<Date(); s.intervalLabel = "last week" }
        return s
    }

    @Test func timeReport_whenWantsTimeTotals() {
        #expect(ChatLensSelector.select(scope: scope(totals: true), question: "how many weeks on each project") == .timeReport)
        // time intent wins even with a summary verb present
        #expect(ChatLensSelector.select(scope: scope(totals: true, interval: true), question: "summarise my time") == .timeReport)
    }

    @Test func activityDigest_whenIntervalBoundedRecap() {
        #expect(ChatLensSelector.select(scope: scope(interval: true), question: "summarise my last week") == .activityDigest)
        #expect(ChatLensSelector.select(scope: scope(interval: true), question: "what did I do last week") == .activityDigest)
    }

    @Test func openBox_otherwise() {
        // Recap verb but no interval → open box.
        #expect(ChatLensSelector.select(scope: scope(), question: "summarise the NODES project") == .openBox)
        // Plain lookup.
        #expect(ChatLensSelector.select(scope: scope(interval: true), question: "who is on the NODES team") == .openBox)
    }
}
