import Foundation
import Testing
@testable import gbpDiary

struct ChatAnswerMarkdownTests {
    @Test func convertsNewlinesToHardBreaks() {
        // Single newlines become CommonMark hard breaks so line-per-item answers keep their layout.
        #expect(ChatAnswerMarkdown.render("Line one\nLine two") == "Line one  \nLine two")
        #expect(ChatAnswerMarkdown.render("• A\n• B") == "• A  \n• B")
    }

    @Test func noNewlines_unchanged() {
        #expect(ChatAnswerMarkdown.render("Just one line") == "Just one line")
    }
}
