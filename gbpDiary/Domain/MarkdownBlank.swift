import Foundation

// Decides whether a markdown note has no *visible* text — used by MarkdownDocumentEditor to show the
// tap-to-edit placeholder. A note counts as blank when every line is empty or only empty markdown
// scaffolding: blockquote markers (`>`), a bullet/ordered list marker (`-`/`*`/`+`/`1.`/`1)`) with an
// optional empty checkbox (`[ ]`), or a heading marker (`#`…`######`) — with no text after it. A lone
// "- " left behind by list editing is therefore blank, while "- item" is not.
enum MarkdownBlank {
    // Each line: optional leading whitespace, any number of `>` quote markers, then optionally a single
    // heading/list marker (with an optional checkbox for list items), then only whitespace to end.
    private static let linePattern = "^\\s*(>\\s*)*((#{1,6}|[-*+]|\\d+[.)])(\\s+\\[[ xX]\\])?\\s*)?$"

    static func isBlank(_ markdown: String) -> Bool {
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if String(line).range(of: linePattern, options: .regularExpression) == nil { return false }
        }
        return true
    }
}
