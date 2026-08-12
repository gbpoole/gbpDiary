import Foundation
import Testing
@testable import gbpDiary

struct MarkdownHTMLTests {
    private func html(_ md: String) -> String {
        MarkdownHTML.render(md, image: { _ in nil })
    }

    @Test func heading() {
        #expect(html("## Agenda") == "<h2>Agenda</h2>")
    }

    @Test func paragraph_escapesAndFormatsInline() {
        let out = html("a < b & **bold** and *em* and `x<y`")
        #expect(out.contains("a &lt; b &amp;"))
        #expect(out.contains("<strong>bold</strong>"))
        #expect(out.contains("<em>em</em>"))
        #expect(out.contains("<code>x&lt;y</code>"))
        #expect(out.hasPrefix("<p>"))
    }

    @Test func link_andNoteLink() {
        let out = html("see [site](https://x.com) and [note](note://\(UUID().uuidString))")
        #expect(out.contains("<a href=\"https://x.com\">site</a>"))
        #expect(out.contains("note"))          // internal note link kept as plain text
        #expect(!out.contains("note://"))       // ...not as an href
    }

    @Test func image_usesResolvedSrcAndWidth() {
        let id = UUID()
        let md = AttachmentRef.markdown(for: id, displayName: "Chart")
        let out = MarkdownHTML.render(md) { attID in
            attID == id ? MarkdownHTML.ImageInfo(src: "\(id).png", widthPercent: 50) : nil
        }
        #expect(out.contains("<img src=\"\(id).png\""))
        #expect(out.contains("width:50%"))
        #expect(out.contains("alt=\"Chart\""))
    }

    @Test func image_noWidth_usesFullWidth() {
        let id = UUID()
        let md = AttachmentRef.markdown(for: id, displayName: "x")
        let out = MarkdownHTML.render(md) { _ in MarkdownHTML.ImageInfo(src: "a.png", widthPercent: nil) }
        #expect(out.contains("max-width:100%"))
    }

    @Test func unorderedList_withCheckbox() {
        let out = html("- one\n- [ ] todo\n- [x] done")
        #expect(out.contains("<ul>"))
        #expect(out.contains("<li>one</li>"))
        #expect(out.contains("type=\"checkbox\" disabled> todo"))
        #expect(out.contains("checked disabled> done"))
    }

    @Test func orderedList() {
        let out = html("1. first\n2. second")
        #expect(out.contains("<ol>"))
        #expect(out.contains("<li>first</li>"))
        #expect(out.contains("<li>second</li>"))
    }

    @Test func blockquote() {
        #expect(html("> quoted").contains("<blockquote>quoted</blockquote>"))
    }

    @Test func fencedCode_escaped() {
        let out = html("```\nlet x = a < b\n```")
        #expect(out.contains("<pre><code>let x = a &lt; b</code></pre>"))
    }

    @Test func horizontalRule() {
        #expect(html("a\n\n---\n\nb").contains("<hr>"))
    }

    @Test func table() {
        let out = html("| A | B |\n| --- | --- |\n| 1 | 2 |")
        #expect(out.contains("<table>"))
        #expect(out.contains("<th>A</th>"))
        #expect(out.contains("<td>1</td>"))
    }
}
