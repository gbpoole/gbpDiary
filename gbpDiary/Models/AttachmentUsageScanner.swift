import Foundation

// Determines which attachments are still referenced by note markdown and which are orphaned.
//
// An attachment is "used" if its id appears as an `attachment://<uuid>` image reference in any
// note's markdown content. Attachments referenced nowhere are orphans and can be cleaned up from
// the image library. Pure helper (no SwiftData) so it is unit-testable — callers pass in the raw
// markdown strings and the candidate attachment ids.
enum AttachmentUsageScanner {

    /// The set of attachment ids referenced by any of the supplied markdown strings.
    static func referencedIDs(inContents contents: [String]) -> Set<UUID> {
        var used: Set<UUID> = []
        for markdown in contents {
            used.formUnion(AttachmentRef.referencedIDs(in: markdown))
        }
        return used
    }

    /// Given all candidate attachment ids and all note markdown, returns the ids referenced by
    /// no content (orphans).
    static func orphanedIDs(candidates: [UUID], contents: [String]) -> Set<UUID> {
        let used = referencedIDs(inContents: contents)
        return Set(candidates).subtracting(used)
    }
}
