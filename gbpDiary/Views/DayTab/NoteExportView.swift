#if os(macOS)
import SwiftUI
import AppKit

// Rendered off-screen by DayNoteRow.exportAsPDF() via NSHostingView.dataWithPDF.
// Always forced to light mode so PDF colours are stable regardless of system theme.
//
// StructuredText (Textual) uses multi-pass SwiftUI layout (preference keys, @State) so
// only the first layout pass is captured by dataWithPDF — tables and list item text are
// silently dropped. Instead, markdown is converted to HTML and rendered via
// NSAttributedString(html:) → NSTextView, which draws into the CoreGraphics PDF context
// in a single pass. Images come from note.attachments (not inline markdown links) and
// are rendered via PDFImageView (NSViewRepresentable + NSImageView).
struct NoteExportView: View {
    let note: Note
    let date: Date?

    // Content area = 612pt (US Letter) − 2 × 56pt padding
    private static let contentWidth: CGFloat = 500

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider().padding(.vertical, 20)
            contentSection
            Spacer(minLength: 48)
        }
        .padding(56)
        .frame(width: 612)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: - Header

    @ViewBuilder private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exportTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.black)

            if date != nil || note.project != nil {
                HStack(spacing: 0) {
                    if let date {
                        Label(date.formatted(date: .long, time: .omitted), systemImage: "calendar")
                    }
                    if date != nil && note.project != nil { Text("   ·   ") }
                    if let project = note.project {
                        Label(project.name, systemImage: "folder")
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary)
            }

            if !note.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(note.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.teal.opacity(0.12))
                            .foregroundStyle(Color.teal)
                            .clipShape(Capsule())
                    }
                }
            }

            Text(timestampLine)
                .font(.system(size: 10))
                .foregroundStyle(Color.gray.opacity(0.6))
        }
    }

    // MARK: - Content

    @ViewBuilder private var contentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(note.blocks) { block in
                switch block.kind {
                case .text:
                    if !block.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        PDFMarkdownView(content: block.textContent, width: Self.contentWidth)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                case .image:
                    if let att = note.attachments.first(where: { $0.id == block.attachmentId }),
                       let img = NSImage(contentsOf: att.fileURL) {
                        // Use source image for maximum PDF quality.
                        // Display width matches the UI: renderWidth capped at content width.
                        let displayW = min(CGFloat(att.renderWidth ?? Int(img.size.width)),
                                          Self.contentWidth)
                        let scale = displayW / img.size.width
                        let pdfAlignment: Alignment = switch block.alignment {
                            case .left:   .leading
                            case .center: .center
                            case .right:  .trailing
                        }
                        PDFImageView(image: img)
                            .frame(width: displayW, height: img.size.height * scale)
                            .frame(maxWidth: .infinity, alignment: pdfAlignment)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    var exportTitle: String {
        for block in note.blocks where block.kind == .text {
            for rawLine in block.textContent.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = String(rawLine).trimmingCharacters(in: .whitespaces)
                let stripped = line.replacingOccurrences(of: "^#+\\s+", with: "", options: .regularExpression)
                if !stripped.isEmpty { return String(stripped.prefix(80)) }
            }
        }
        if let date { return date.formatted(date: .long, time: .omitted) }
        return "Note"
    }

    private var timestampLine: String {
        let created = "Created \(note.createdAt.formatted(date: .abbreviated, time: .shortened))"
        guard note.updatedAt.timeIntervalSince(note.createdAt) > 60 else { return created }
        return "\(created)  ·  Updated \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

// MARK: - PDFMarkdownView
//
// NSTextView renders markdown (converted to HTML via NSAttributedString) in a single
// CoreText pass — compatible with NSHostingView.dataWithPDF. AutosizingTextView
// overrides intrinsicContentSize so SwiftUI can measure the laid-out height correctly.

private struct PDFMarkdownView: NSViewRepresentable {
    let content: String
    let width: CGFloat

    func makeNSView(context: Context) -> AutosizingTextView {
        let tv = AutosizingTextView()
        tv.isEditable = false
        tv.isSelectable = false
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        configure(tv)
        return tv
    }

    func updateNSView(_ tv: AutosizingTextView, context: Context) {
        configure(tv)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: AutosizingTextView, context: Context) -> CGSize? {
        guard let container = tv.textContainer, let manager = tv.layoutManager else { return nil }
        manager.ensureLayout(for: container)
        let height = manager.usedRect(for: container).height
        return CGSize(width: proposal.width ?? width, height: height)
    }

    private func configure(_ tv: AutosizingTextView) {
        tv.textContainer?.containerSize = CGSize(width: width, height: 1_000_000)
        guard let storage = tv.textStorage else { return }
        let html = markdownToHTML(content)
        guard let data = html.data(using: .utf8),
              let attrStr = NSAttributedString(
                  html: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue
                  ],
                  documentAttributes: nil
              ) else {
            storage.setAttributedString(NSAttributedString(string: content))
            return
        }
        storage.setAttributedString(attrStr)
        tv.invalidateIntrinsicContentSize()
    }
}

private final class AutosizingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let manager = layoutManager else {
            return super.intrinsicContentSize
        }
        manager.ensureLayout(for: container)
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: manager.usedRect(for: container).height)
    }
}

// MARK: - PDFImageView
//
// Wraps NSImageView so that NSImage.draw(in:) is called during dataWithPDF rendering.
// SwiftUI's Image(nsImage:) routes through a display-optimised path that does not write
// into the CoreGraphics PDF context produced by NSHostingView.dataWithPDF.
private struct PDFImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleAxesIndependently
        v.image = image
        return v
    }

    func updateNSView(_ v: NSImageView, context: Context) {
        v.image = image
    }
}

// MARK: - Markdown → HTML

// Converts the subset of GitHub-flavoured markdown used in notes to HTML so that
// NSAttributedString(html:) can render it with correct block-level formatting.
// Handles: headings, unordered/ordered lists, tables, fenced code blocks,
// blockquotes, thematic breaks, and inline bold/italic/code.
private func markdownToHTML(_ markdown: String) -> String {
    func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&",  with: "&amp;")
         .replacingOccurrences(of: "<",  with: "&lt;")
         .replacingOccurrences(of: ">",  with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
    func inlines(_ s: String) -> String {
        var r = escapeHTML(s)
        r = r.replacingOccurrences(of: #"\*\*\*(.+?)\*\*\*"#, with: "<strong><em>$1</em></strong>", options: .regularExpression)
        r = r.replacingOccurrences(of: #"\*\*(.+?)\*\*"#,     with: "<strong>$1</strong>",           options: .regularExpression)
        r = r.replacingOccurrences(of: #"__(.+?)__"#,          with: "<strong>$1</strong>",           options: .regularExpression)
        r = r.replacingOccurrences(of: #"(?<!\*)\*([^*\n]+?)\*(?!\*)"#, with: "<em>$1</em>",          options: .regularExpression)
        r = r.replacingOccurrences(of: #"(?<!_)_([^_\n]+?)_(?!_)"#,    with: "<em>$1</em>",          options: .regularExpression)
        r = r.replacingOccurrences(of: #"`([^`\n]+?)`"#,       with: "<code>$1</code>",               options: .regularExpression)
        return r
    }
    func parseTableRow(_ line: String, isHeader: Bool) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s = String(s.dropFirst()) }
        if s.hasSuffix("|") { s = String(s.dropLast()) }
        let cells = s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let tag = isHeader ? "th" : "td"
        return "<tr>" + cells.map { "<\(tag)>\(inlines($0))</\(tag)>" }.joined() + "</tr>"
    }

    let css = """
    <html><head><meta charset='utf-8'><style>
    body{font-family:-apple-system,Helvetica,sans-serif;font-size:13px;color:#000;\
    line-height:1.5;margin:0;padding:0}
    h1{font-size:20px;font-weight:700;margin:14px 0 6px}
    h2{font-size:17px;font-weight:700;margin:12px 0 5px}
    h3{font-size:14px;font-weight:700;margin:10px 0 4px}
    h4,h5,h6{font-size:13px;font-weight:700;margin:8px 0 3px}
    p{margin:0 0 8px}
    ul,ol{margin:0 0 8px;padding-left:22px}
    li{margin-bottom:2px}
    table{border-collapse:collapse;margin:8px 0;width:100%}
    th,td{border:1px solid #ccc;padding:4px 8px;text-align:left;font-size:12px}
    th{font-weight:700;background-color:#f6f8fa}
    pre{background-color:#f6f8fa;padding:8px;border-radius:3px;margin:8px 0;white-space:pre-wrap}
    code{font-family:ui-monospace,monospace;font-size:11px;background-color:#f6f8fa;\
    padding:1px 4px;border-radius:2px}
    pre code{background:none;padding:0}
    blockquote{border-left:3px solid #ccc;margin:4px 0 8px 0;padding:0 12px;color:#555}
    hr{border:none;border-top:1px solid #ddd;margin:12px 0}
    </style></head><body>
    """

    let lines = markdown.components(separatedBy: "\n")
    var out = css
    var i = 0
    var paraLines: [String] = []
    var inFence = false
    var fenceLines: [String] = []

    func flushPara() {
        guard !paraLines.isEmpty else { return }
        let text = paraLines.joined(separator: "<br>")
        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            out += "<p>\(inlines(text))</p>\n"
        }
        paraLines = []
    }

    while i < lines.count {
        let line = lines[i]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Fenced code block
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            if inFence {
                out += "<pre><code>\(escapeHTML(fenceLines.joined(separator: "\n")))</code></pre>\n"
                inFence = false
                fenceLines = []
            } else {
                flushPara()
                inFence = true
            }
            i += 1; continue
        }
        if inFence { fenceLines.append(line); i += 1; continue }

        // ATX heading
        if let range = trimmed.range(of: "^(#{1,6}) +", options: .regularExpression) {
            flushPara()
            let level = trimmed[range].filter { $0 == "#" }.count
            let content = String(trimmed[range.upperBound...])
            out += "<h\(level)>\(inlines(content))</h\(level)>\n"
            i += 1; continue
        }

        // Thematic break
        if trimmed.range(of: "^(---+|\\*\\*\\*+|___+)$", options: .regularExpression) != nil {
            flushPara()
            out += "<hr>\n"
            i += 1; continue
        }

        // Unordered list — collect consecutive items
        if trimmed.range(of: "^[-*+] ", options: .regularExpression) != nil {
            flushPara()
            out += "<ul>\n"
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                guard l.range(of: "^[-*+] ", options: .regularExpression) != nil else { break }
                out += "<li>\(inlines(String(l.dropFirst(2))))</li>\n"
                i += 1
            }
            out += "</ul>\n"; continue
        }

        // Ordered list — collect consecutive items
        if trimmed.range(of: "^\\d+\\. ", options: .regularExpression) != nil {
            flushPara()
            out += "<ol>\n"
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                guard l.range(of: "^\\d+\\. ", options: .regularExpression) != nil else { break }
                if let r = l.range(of: "^\\d+\\. ", options: .regularExpression) {
                    out += "<li>\(inlines(String(l[r.upperBound...])))</li>\n"
                }
                i += 1
            }
            out += "</ol>\n"; continue
        }

        // Table — header + separator + rows
        if trimmed.hasPrefix("|") {
            flushPara()
            var tableLines: [String] = []
            while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                tableLines.append(lines[i])
                i += 1
            }
            if tableLines.count >= 2 {
                out += "<table>\n"
                out += parseTableRow(tableLines[0], isHeader: true) + "\n"
                for row in tableLines.dropFirst(2) {
                    out += parseTableRow(row, isHeader: false) + "\n"
                }
                out += "</table>\n"
            }
            continue
        }

        // Blockquote
        if trimmed.hasPrefix("> ") {
            flushPara()
            out += "<blockquote>\(inlines(String(trimmed.dropFirst(2))))</blockquote>\n"
            i += 1; continue
        }

        // Empty line
        if trimmed.isEmpty {
            flushPara()
            i += 1; continue
        }

        // Regular paragraph line
        paraLines.append(line)
        i += 1
    }

    flushPara()
    out += "</body></html>"
    return out
}
#endif
