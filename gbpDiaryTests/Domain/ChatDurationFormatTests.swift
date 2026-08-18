import Foundation
import Testing
@testable import gbpDiary

struct ChatDurationFormatTests {
    @Test func subSecond_showsMilliseconds() {
        #expect(ChatDurationFormat.short(0) == "0 ms")
        #expect(ChatDurationFormat.short(0.82) == "820 ms")
        #expect(ChatDurationFormat.short(-1) == "0 ms")   // clamped
    }

    @Test func atLeastASecond_showsOneDecimal() {
        #expect(ChatDurationFormat.short(1) == "1.0 s")
        #expect(ChatDurationFormat.short(1.44) == "1.4 s")
        #expect(ChatDurationFormat.short(12.5) == "12.5 s")
    }
}
