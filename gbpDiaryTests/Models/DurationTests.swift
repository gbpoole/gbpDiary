import Testing
@testable import gbpDiary

@MainActor
struct DurationTests {
    @Test func parse_validInputs_normalizesHours() {
        let h = Duration.parse("1.5h")
        let d = Duration.parse("2d")
        let w = Duration.parse("1w")

        #expect(h?.hoursNormalized == 1.5)
        #expect(d?.hoursNormalized == 15.2)
        #expect(w?.hoursNormalized == 38.0)
    }

    @Test func parse_invalidInputs_returnsNil() {
        #expect(Duration.parse("") == nil)
        #expect(Duration.parse("1") == nil)
        #expect(Duration.parse("0h") == nil)
        #expect(Duration.parse("-2d") == nil)
        #expect(Duration.parse("2x") == nil)
    }

    @Test func displayString_formatsWholeAndFractional() {
        #expect(Duration(value: 1, unit: .h).displayString == "1h")
        #expect(Duration(value: 1.5, unit: .h).displayString == "1.5h")
    }
}
