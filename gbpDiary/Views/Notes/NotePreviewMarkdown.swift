import Foundation

// Prepares a note's markdown for rendering by Textual's StructuredText.
//
// 1. Rewrites managed image refs `attachment://<uuid>` → the attachment's on-disk `file://` URL
//    so Textual's default image loader can display them.
// 2. Converts single newlines into markdown hard breaks (`  \n`) so day-to-day note text wraps
//    the way users expect without needing blank lines between every line.
enum NotePreviewMarkdown {

    /// - Parameter resolve: maps an attachment id to its absolute file URL (nil if missing).
    static func render(_ markdown: String, resolve: (UUID) -> URL?) -> String {
        var out = markdown
        for id in AttachmentRef.referencedIDs(in: markdown) {
            let token = AttachmentRef.url(for: id)
            let replacement = resolve(id)?.absoluteString ?? token
            out = out.replacingOccurrences(of: token, with: replacement)
        }
        return out.replacingOccurrences(of: "\n", with: "  \n")
    }
}
