import Foundation

// Splits note markdown into an ordered sequence of text runs and inline image references, so a PDF
// exporter can render text via HTML/NSAttributedString and images as separate sized views (SwiftUI
// `Image`/HTML `<img>` don't size/draw correctly in the PDF context — see MinutesExportView).
enum NotePDFSegment: Equatable {
    case text(String)
    case image(UUID)
}

enum NotePDFSegments {
    // Matches a managed image ref `![alt](attachment://<uuid>)`.
    private static let pattern =
        "!\\[[^\\]]*\\]\\(attachment://([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\\)"

    static func segments(from markdown: String) -> [NotePDFSegment] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return markdown.isEmpty ? [] : [.text(markdown)]
        }
        let ns = markdown as NSString
        var result: [NotePDFSegment] = []
        var last = 0

        func appendText(_ range: NSRange) {
            let text = ns.substring(with: range)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.text(text))
            }
        }

        for match in regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            appendText(NSRange(location: last, length: match.range.location - last))
            if let id = UUID(uuidString: ns.substring(with: match.range(at: 1))) {
                result.append(.image(id))
            }
            last = match.range.location + match.range.length
        }
        appendText(NSRange(location: last, length: ns.length - last))
        return result
    }
}
