import Foundation

// Keeps the SwiftUI text binding and the NSTextView buffer of ImageChipTextEditor in sync without letting
// a *stale echo* of the user's own typing revert the buffer.
//
// The coordinator pushes each self-originated edit back to SwiftUI asynchronously (deferred to avoid a
// mid-edit layout storm) while updating its `lastMarkdown` synchronously. That lag means `updateNSView`
// can receive an older value than the buffer already holds; naively rebuilding for it clamps the caret and
// scrambles recently-typed text. This helper decides, from the queue of not-yet-reconciled self pushes,
// whether an incoming binding value is a genuine external change (rebuild) or just such a stale echo (skip).
enum MarkdownEditorSync {
    /// Whether `updateNSView` must rebuild the text view. Mutates `pendingEchoes`: cleared when the
    /// incoming value already matches the buffer, the matched stale echo (and anything before it) is
    /// consumed when found, and cleared for a genuine external change. Returns true only for the latter.
    static func shouldRebuild(incoming: String, buffer: String, pendingEchoes: inout [String]) -> Bool {
        if incoming == buffer {
            pendingEchoes.removeAll()   // in sync; no stale echo can matter
            return false
        }
        if let idx = pendingEchoes.firstIndex(of: incoming) {
            pendingEchoes.removeFirst(idx + 1)   // stale self-echo — ignore, drop up to and incl. it
            return false
        }
        pendingEchoes.removeAll()
        return true   // genuine external change
    }
}
