import Foundation
import Testing
@testable import gbpDiary

struct AISummaryStyleTests {
    @Test func directive_encodesSecondPersonSimplePastNeutralNoMarkdown() {
        let d = AISummaryStyle.directive
        #expect(d.contains("\"you\""))            // second person
        #expect(d.lowercased().contains("simple past"))
        #expect(d.lowercased().contains("neutral"))
        #expect(d.lowercased().contains("markdown"))  // the "no markdown" format rule
        // Rendered as a bullet block, one line per rule.
        #expect(d.contains("• "))
        #expect(d.components(separatedBy: "\n").count == AISummaryStyle.rules.count)
    }

    @Test func inline_isOneLineSecondPersonSimplePast() {
        let i = AISummaryStyle.inline
        #expect(!i.contains("\n"))
        #expect(i.contains("second person"))
        #expect(i.contains("simple past tense"))
        #expect(i.contains("professional"))
    }

    @Test func version_isPositive() {
        #expect(AISummaryStyle.version >= 1)
    }
}
