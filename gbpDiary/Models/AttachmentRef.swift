import Foundation

// Managed-image reference scheme for markdown notes.
//
// Images are never stored as file paths in note markdown. Instead they embed as a standard
// CommonMark image whose URL uses the custom `attachment://<uuid>` scheme:
//
//     ![Display Name](attachment://5E9C0B2A-…-uuid)
//
// The alt text carries a human-friendly display name; the UUID resolves to an `Attachment`.
// This keeps note content valid markdown (renders/degrades anywhere) while decoupling it from
// on-disk filenames. `AttachmentRef` is a pure helper (no SwiftData) so it is unit-testable.
enum AttachmentRef {
    static let scheme = "attachment"

    /// The canonical URL string for an attachment id, e.g. `attachment://<uuid>`.
    static func url(for id: UUID) -> String { "\(scheme)://\(id.uuidString)" }

    /// A full markdown image node referencing the attachment.
    static func markdown(for id: UUID, displayName: String?) -> String {
        let alt = (displayName ?? "").replacingOccurrences(of: "]", with: " ")
        return "![\(alt)](\(url(for: id)))"
    }

    /// Parses an `attachment://<uuid>` URL string back into a UUID, or nil if it isn't one.
    static func id(fromURL urlString: String) -> UUID? {
        guard let url = URL(string: urlString),
              url.scheme == scheme else { return nil }
        // For attachment://<uuid> the uuid lands in the host; be tolerant of path form too.
        let candidate = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UUID(uuidString: candidate)
    }

    private static let imageRefRegex = try! NSRegularExpression(
        pattern: #"!\[[^\]]*\]\(\s*attachment://([0-9A-Fa-f-]{36})\s*\)"#
    )

    /// All attachment ids referenced by image nodes in a markdown string, in order of appearance.
    static func referencedIDs(in markdown: String) -> [UUID] {
        let ns = markdown as NSString
        let matches = imageRefRegex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { m in
            guard m.numberOfRanges > 1 else { return nil }
            return UUID(uuidString: ns.substring(with: m.range(at: 1)))
        }
    }
}
