import Foundation

// Computes note-to-note backlinks: given a target note and all note contents, returns the ids of
// the notes whose markdown links to the target via a `note://<uuid>` reference. Pure helper (no
// SwiftData) so it is unit-testable — callers pass in (id, content) pairs.
enum NoteLinkUsageScanner {

    /// The ids of notes that reference `id` in their content, excluding `id` itself, in the order
    /// the notes are supplied.
    static func backlinks(to id: UUID, in notes: [(id: UUID, content: String)]) -> [UUID] {
        notes.compactMap { note in
            guard note.id != id else { return nil }
            return NoteLinkRef.referencedIDs(in: note.content).contains(id) ? note.id : nil
        }
    }
}
