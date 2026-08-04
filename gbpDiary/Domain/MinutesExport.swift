import Foundation

// Pure helpers for exporting a note's markdown to a portable file/bundle: rewrite managed image refs
// (`attachment://<uuid>`) to relative paths that point at the copied image files, so the exported
// markdown renders in any editor. The file I/O + zipping lives in the view layer (macOS).
enum MinutesExport {
    /// Replace each `attachment://<uuid>` image ref with a relative path (e.g. `images/<file>`).
    /// Refs with no mapping are left as-is.
    static func rewriteImageLinks(_ markdown: String, relativePath: (UUID) -> String?) -> String {
        var out = markdown
        for id in AttachmentRef.referencedIDs(in: markdown) {
            guard let rel = relativePath(id) else { continue }
            out = out.replacingOccurrences(of: AttachmentRef.url(for: id), with: rel)
        }
        return out
    }

    /// A collision-free in-bundle file name for an attachment: `<uuid>.<ext>` (ext taken from the
    /// original file name; omitted when there is none).
    static func bundleFileName(id: UUID, originalFileName: String) -> String {
        let ext = (originalFileName as NSString).pathExtension
        return ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)"
    }

    /// Initials from a person's name: first letter of each whitespace-separated word, uppercased
    /// ("Ada Lovelace" → "AL", "madonna" → "M"). Empty for a blank name.
    static func initials(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace })
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()
    }

    /// Composes the full export markdown: a header (title + date line + metadata lines), an
    /// **Action Items** list (`_None._` when empty), an optional **Documents** list (omitted when
    /// empty), then the minutes body after a `---` rule. Pure so it's testable; the view gathers the
    /// pieces.
    static func composeMarkdown(title: String, dateLine: String, metaLines: [String],
                                actionItems: [String], documents: [String], body: String) -> String {
        // Header: title with the date immediately beneath it (then any metadata lines).
        var header = "# \(title.isEmpty ? "Meeting" : title)"
        if !dateLine.isEmpty { header += "\n\(dateLine)" }
        for line in metaLines { header += "\n\(line)" }

        // Blank line then a `---` rule separates the header from the Action Items / Documents lists.
        var blocks: [String] = [header, "---"]

        blocks.append("## Action Items\n"
            + (actionItems.isEmpty ? "_None._" : actionItems.map { "- \($0)" }.joined(separator: "\n")))

        if !documents.isEmpty {
            blocks.append("## Documents\n" + documents.map { "- \($0)" }.joined(separator: "\n"))
        }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            blocks.append("---")
            blocks.append(trimmedBody)
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    /// Sanitises a meeting summary into a safe base file name (letters/digits/`-_ ` kept), or a
    /// fallback when empty.
    static func exportBaseName(summary: String?, fallback: String = "Minutes") -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = (summary ?? "")
            .components(separatedBy: allowed.inverted).joined()
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? fallback : cleaned
    }
}
