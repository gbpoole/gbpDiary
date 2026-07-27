import Foundation

// Note-to-note link reference scheme for markdown notes.
//
// Content notes link to each other via a standard CommonMark link whose URL uses the custom
// `note://<uuid>` scheme:
//
//     [Display Title](note://5E9C0B2A-…-uuid)
//
// The link text carries the target note's title; the UUID resolves to a `Note`. Keeping links as
// ordinary markdown means they render/degrade anywhere, while decoupling from titles that may
// change. `NoteLinkRef` is a pure helper (no SwiftData) so it is unit-testable and mirrors
// `AttachmentRef`.
enum NoteLinkRef {
    static let scheme = "note"

    /// The canonical URL string for a note id, e.g. `note://<uuid>`.
    static func url(for id: UUID) -> String { "\(scheme)://\(id.uuidString)" }

    /// A full markdown link node referencing the note.
    static func markdown(for id: UUID, displayName: String?) -> String {
        let text = (displayName ?? "").replacingOccurrences(of: "]", with: " ")
        return "[\(text)](\(url(for: id)))"
    }

    /// Parses a `note://<uuid>` URL string back into a UUID, or nil if it isn't one.
    static func id(fromURL urlString: String) -> UUID? {
        guard let url = URL(string: urlString),
              url.scheme == scheme else { return nil }
        // For note://<uuid> the uuid lands in the host; be tolerant of path form too.
        let candidate = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UUID(uuidString: candidate)
    }

    private static let linkRefRegex = try! NSRegularExpression(
        pattern: #"\[[^\]]*\]\(\s*note://([0-9A-Fa-f-]{36})\s*\)"#
    )

    /// All note ids referenced by link nodes in a markdown string, in order of appearance.
    static func referencedIDs(in markdown: String) -> [UUID] {
        let ns = markdown as NSString
        let matches = linkRefRegex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { m in
            guard m.numberOfRanges > 1 else { return nil }
            return UUID(uuidString: ns.substring(with: m.range(at: 1)))
        }
    }
}
