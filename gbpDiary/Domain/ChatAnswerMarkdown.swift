import Foundation

// Prepares a Chat answer for rendering by Textual's StructuredText. Answers are markdown (the model emits
// bold/lists/headings; the deterministic lenses emit line-per-item blocks), but CommonMark collapses
// single newlines into spaces — so, like NotePreviewMarkdown, convert every newline to a hard break so the
// line structure the answer intends is preserved. Pure/testable.
nonisolated enum ChatAnswerMarkdown {
    static func render(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: "  \n")
    }
}
