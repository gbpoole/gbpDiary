import Foundation

// Decides whether a `Note` belongs to the free-standing "Content" vault. A content note is one
// with a non-empty title that is not owned by a day or a meeting (it may still carry a project).
// Pure helper (no SwiftData) so the membership rule is unit-testable independently of the model.
enum NoteContentMembership {
    static func isContentNote(title: String, hasDayRecord: Bool, hasMinutes: Bool) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasDayRecord
            && !hasMinutes
    }
}
