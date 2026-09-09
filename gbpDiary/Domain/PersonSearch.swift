import Foundation

// Free-text search for the People page. Matches a query against each of a person's fields *individually*
// rather than one concatenated string — so a query can't span across fields (e.g. "sam" matching
// "Rosa M." <rosa@x> because s·a·m appear in order across name+email), and every email is searchable
// (not just the primary one).
enum PersonSearch {
    /// True when the query fuzzy-matches (in-order subsequence, case-insensitive — see FuzzyMatch) at
    /// least one field: the name, any email, the institution name, or any tag. Empty query matches all.
    static func matches(query: String, name: String, emails: [String],
                        institution: String?, tags: [String]) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        var fields = [name]
        fields.append(contentsOf: emails)
        if let institution { fields.append(institution) }
        fields.append(contentsOf: tags)
        return fields.contains { FuzzyMatch.matches(q, in: $0) }
    }
}
