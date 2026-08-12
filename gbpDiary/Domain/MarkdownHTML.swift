import Foundation

// A compact, dependency-free Markdown → HTML converter for exporting notes/minutes to PDF (via
// WKWebView). Covers the constructs notes actually use: headings, paragraphs, bold/italic/inline-code,
// links, images (with a per-image display width), unordered/ordered lists incl. checkboxes,
// blockquotes, fenced code blocks, horizontal rules, and pipe tables. It is intentionally pragmatic —
// not a full CommonMark implementation — and every text run is HTML-escaped.
enum MarkdownHTML {
    /// Resolved image info for an `attachment://<uuid>` ref: the `<img>` src to use and an optional
    /// display width as a percent of the content width (nil = full width).
    struct ImageInfo {
        let src: String
        let widthPercent: Int?
    }

    /// Convert `markdown` to an HTML fragment. `image` maps a managed-image id to its `ImageInfo`;
    /// return nil to fall back to a plain `<img>` using the raw URL.
    static func render(_ markdown: String, image: (UUID) -> ImageInfo?) -> String {
        var html: [String] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0

        func flushParagraph(_ buffer: inout [String]) {
            guard !buffer.isEmpty else { return }
            let joined = buffer.map { inline($0, image: image) }.joined(separator: "<br>\n")
            html.append("<p>\(joined)</p>")
            buffer.removeAll()
        }

        var paragraph: [String] = []

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block.
            if trimmed.hasPrefix("```") {
                flushParagraph(&paragraph)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(escape(lines[i]))
                    i += 1
                }
                i += 1  // closing fence
                html.append("<pre><code>\(code.joined(separator: "\n"))</code></pre>")
                continue
            }

            // Blank line ends a paragraph.
            if trimmed.isEmpty {
                flushParagraph(&paragraph)
                i += 1
                continue
            }

            // Horizontal rule.
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph(&paragraph)
                html.append("<hr>")
                i += 1
                continue
            }

            // Heading.
            if let heading = headingHTML(trimmed, image: image) {
                flushParagraph(&paragraph)
                html.append(heading)
                i += 1
                continue
            }

            // Table (a header row followed by a |---|---| separator).
            if trimmed.hasPrefix("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushParagraph(&paragraph)
                var rows: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(lines[i]); i += 1
                }
                html.append(tableHTML(rows, image: image))
                continue
            }

            // Blockquote (consecutive `>` lines).
            if trimmed.hasPrefix(">") {
                flushParagraph(&paragraph)
                var quote: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let content = String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)
                    quote.append(inline(content, image: image))
                    i += 1
                }
                html.append("<blockquote>\(quote.joined(separator: "<br>\n"))</blockquote>")
                continue
            }

            // Lists (unordered / ordered, incl. checkboxes).
            if listMarker(trimmed) != nil {
                flushParagraph(&paragraph)
                let ordered = orderedMarker(trimmed) != nil
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty, listMarker(t) != nil, (orderedMarker(t) != nil) == ordered else { break }
                    items.append(listItemHTML(t, image: image))
                    i += 1
                }
                let tag = ordered ? "ol" : "ul"
                html.append("<\(tag)>\n" + items.map { "<li>\($0)</li>" }.joined(separator: "\n") + "\n</\(tag)>")
                continue
            }

            // Otherwise, accumulate into the current paragraph.
            paragraph.append(line)
            i += 1
        }
        flushParagraph(&paragraph)
        return html.joined(separator: "\n")
    }

    // MARK: - Blocks

    private static func headingHTML(_ line: String, image: (UUID) -> ImageInfo?) -> String? {
        var level = 0
        for ch in line { if ch == "#" { level += 1 } else { break } }
        guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
        let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        return "<h\(level)>\(inline(text, image: image))</h\(level)>"
    }

    private static func listMarker(_ t: String) -> String? {
        if let o = orderedMarker(t) { return o }
        if let first = t.first, "-*+".contains(first), t.dropFirst().first == " " { return String(first) }
        return nil
    }

    private static func orderedMarker(_ t: String) -> String? {
        let digits = t.prefix { $0.isNumber }
        guard !digits.isEmpty, t.dropFirst(digits.count).first == "." else { return nil }
        return String(digits)
    }

    private static func listItemHTML(_ t: String, image: (UUID) -> ImageInfo?) -> String {
        // Strip the marker.
        var content: String
        if let digits = orderedMarker(t) {
            content = String(t.dropFirst(digits.count + 1)).trimmingCharacters(in: .whitespaces)
        } else {
            content = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        // Checkbox prefix.
        var checkbox = ""
        let lower = content.lowercased()
        if lower.hasPrefix("[ ] ") {
            checkbox = "<input type=\"checkbox\" disabled> "
            content = String(content.dropFirst(4))
        } else if lower.hasPrefix("[x] ") {
            checkbox = "<input type=\"checkbox\" checked disabled> "
            content = String(content.dropFirst(4))
        }
        return checkbox + inline(content, image: image)
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|") else { return false }
        return t.allSatisfy { "|-: ".contains($0) } && t.contains("-")
    }

    private static func tableCells(_ row: String) -> [String] {
        var t = row.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func tableHTML(_ rows: [String], image: (UUID) -> ImageInfo?) -> String {
        guard let header = rows.first else { return "" }
        let headerCells = tableCells(header).map { "<th>\(inline($0, image: image))</th>" }.joined()
        let bodyRows = rows.dropFirst(2).map { row -> String in
            let cells = tableCells(row).map { "<td>\(inline($0, image: image))</td>" }.joined()
            return "<tr>\(cells)</tr>"
        }.joined(separator: "\n")
        return "<table>\n<thead><tr>\(headerCells)</tr></thead>\n<tbody>\n\(bodyRows)\n</tbody>\n</table>"
    }

    // MARK: - Inline

    static func inline(_ text: String, image: (UUID) -> ImageInfo?) -> String {
        // Protect inline code spans so their contents aren't further formatted.
        var placeholders: [String] = []
        func stash(_ html: String) -> String {
            placeholders.append(html)
            return "\u{0}\(placeholders.count - 1)\u{0}"
        }

        var s = text

        // Inline code first (content escaped, protected from later passes).
        s = replace(s, pattern: "`([^`]+)`") { m in
            stash("<code>\(escape(m[1]))</code>")
        }
        // Images: ![alt](url)
        s = replace(s, pattern: "!\\[([^\\]]*)\\]\\(([^)]+)\\)") { m in
            stash(imageTag(alt: m[1], url: m[2], image: image))
        }
        // Links: [text](url)
        s = replace(s, pattern: "\\[([^\\]]*)\\]\\(([^)]+)\\)") { m in
            let url = m[2]
            let label = escape(m[1])
            if url.hasPrefix("note://") { return stash(label) }  // internal links → plain text in PDF
            return stash("<a href=\"\(escapeAttribute(url))\">\(label)</a>")
        }

        // Escape the remaining plain text, then apply bold/italic.
        s = escape(s)
        s = replace(s, pattern: "\\*\\*([^*]+)\\*\\*") { "<strong>\(escape($0[1]))</strong>" }
        s = replace(s, pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)") { "<em>\(escape($0[1]))</em>" }
        s = replace(s, pattern: "(?<!_)_([^_]+)_(?!_)") { "<em>\(escape($0[1]))</em>" }

        // Restore protected spans.
        for (idx, value) in placeholders.enumerated() {
            s = s.replacingOccurrences(of: "\u{0}\(idx)\u{0}", with: value)
        }
        return s
    }

    private static func imageTag(alt: String, url: String, image: (UUID) -> ImageInfo?) -> String {
        var src = url
        var style = "max-width:100%;height:auto;"
        if let id = AttachmentRef.id(fromURL: url), let info = image(id) {
            src = info.src
            if let w = info.widthPercent { style = "width:\(w)%;height:auto;" }
        }
        return "<img src=\"\(escapeAttribute(src))\" alt=\"\(escapeAttribute(alt))\" style=\"\(style)\">"
    }

    // MARK: - Helpers

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ s: String) -> String {
        escape(s).replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func replace(_ s: String, pattern: String, _ transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            var groups: [String] = []
            for g in 0..<match.numberOfRanges {
                let r = match.range(at: g)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            result += transform(groups)
            last = match.range.location + match.range.length
        }
        result += ns.substring(with: NSRange(location: last, length: ns.length - last))
        return result
    }
}
