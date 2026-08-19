import Foundation
import Testing
@testable import gbpDiary

struct ChatActivityDigestTests {
    private let cal = Calendar(identifier: .gregorian)
    private func d(_ day: Int) -> Date { cal.date(from: DateComponents(year: 2024, month: 1, day: day, hour: 9))! }

    @Test func build_keepsOnlyInWindowItemsSortedByDate() {
        let items = [
            ChatActivityItem(date: d(11), label: "Meeting: B"),
            ChatActivityItem(date: d(9),  label: "Meeting: A"),
            ChatActivityItem(date: d(1),  label: "Meeting: out"),   // before the window
        ]
        let digest = ChatActivityDigestBuilder.build(items: items, interval: d(8)..<d(13))
        #expect(digest.items.map(\.label) == ["Meeting: A", "Meeting: B"])   // sorted, out-of-window dropped
    }

    @Test func render_groupsByDayAndNeverShowsWeekend() {
        // Items are pre-folded to weekdays by the caller, so render only ever prints weekday headers.
        let digest = ChatActivityDigest(items: [
            ChatActivityItem(date: d(9),  label: "Meeting: standup"),
            ChatActivityItem(date: d(9),  label: "Completed: write plan"),
            ChatActivityItem(date: d(10), label: "Meeting: review"),
        ])
        let text = digest.render(calendar: cal)
        #expect(text.contains("Tue 9 Jan:"))
        #expect(text.contains("• Meeting: standup"))
        #expect(text.contains("• Completed: write plan"))
        #expect(text.contains("Wed 10 Jan:"))
        #expect(!text.contains("Sat"))
        #expect(!text.contains("Sun"))
    }

    @Test func empty_rendersEmptyString() {
        #expect(ChatActivityDigest(items: []).render(calendar: cal).isEmpty)
    }

    @Test func sources_dedupById() {
        let ref = ChatSourceReference(id: UUID(), kind: .meeting, title: "M", detail: nil)
        let digest = ChatActivityDigest(items: [
            ChatActivityItem(date: d(9), label: "a", source: ref),
            ChatActivityItem(date: d(9), label: "b", source: ref),
            ChatActivityItem(date: d(9), label: "c", source: nil),
        ])
        #expect(digest.sources.count == 1)
    }

    @Test func phrasingPrompt_isStrictAndCarriesBlock() {
        let prompt = ChatActivityDigestBuilder.phrasingPrompt(block: "Fri 5 Jan:\n• Meeting: X", intervalLabel: "last week")
        #expect(prompt.contains("Use ONLY these items"))
        #expect(prompt.contains("never mention a day that is not listed"))
        #expect(prompt.contains("Fri 5 Jan"))
        #expect(prompt.contains("for last week"))
        #expect(prompt.contains("second person"))   // the shared app-wide voice
        #expect(prompt.contains("simple past"))
    }
}
