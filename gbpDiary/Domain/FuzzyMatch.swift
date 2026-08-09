import Foundation

// Pure fzf-style fuzzy matching: the query characters must appear in order (not necessarily
// contiguous) within the text, case-insensitively. Used to filter the Tasks list.
enum FuzzyMatch {
    /// True if every character of `query` appears in `text` in order (case-insensitive). Empty query matches all.
    static func matches(_ query: String, in text: String) -> Bool {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return true }
        var i = 0
        for ch in text.lowercased() where ch == q[i] {
            i += 1
            if i == q.count { return true }
        }
        return false
    }
}
