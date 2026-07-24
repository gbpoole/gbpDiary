import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct AttachmentRefTests {

    // MARK: - AttachmentRef url/markdown/parse round-trips

    @Test func url_and_id_roundTrip() {
        let id = UUID()
        let url = AttachmentRef.url(for: id)
        #expect(url == "attachment://\(id.uuidString)")
        #expect(AttachmentRef.id(fromURL: url) == id)
    }

    @Test func id_fromURL_rejectsNonAttachmentSchemes() {
        #expect(AttachmentRef.id(fromURL: "https://example.com/\(UUID().uuidString)") == nil)
        #expect(AttachmentRef.id(fromURL: "attachment://not-a-uuid") == nil)
    }

    @Test func markdown_embedsDisplayNameAndRef() {
        let id = UUID()
        let md = AttachmentRef.markdown(for: id, displayName: "Architecture Diagram")
        #expect(md == "![Architecture Diagram](attachment://\(id.uuidString))")
    }

    @Test func markdown_sanitizesClosingBracketInDisplayName() {
        let id = UUID()
        let md = AttachmentRef.markdown(for: id, displayName: "a]b")
        // The closing bracket must not break the alt-text span.
        #expect(!md.contains("a]b"))
        #expect(AttachmentRef.referencedIDs(in: md) == [id])
    }

    // MARK: - referencedIDs extraction

    @Test func referencedIDs_extractsAllInOrder() {
        let a = UUID(); let b = UUID()
        let markdown = """
        Intro text.

        ![First](attachment://\(a.uuidString))

        Middle.

        ![Second](attachment://\(b.uuidString))
        """
        #expect(AttachmentRef.referencedIDs(in: markdown) == [a, b])
    }

    @Test func referencedIDs_ignoresPlainLinksAndNonAttachmentImages() {
        let markdown = """
        [a link](attachment://\(UUID().uuidString))
        ![web image](https://example.com/x.png)
        """
        // The first is a normal link (no leading `!`), the second is not an attachment ref.
        #expect(AttachmentRef.referencedIDs(in: markdown).isEmpty)
    }

    // MARK: - AttachmentUsageScanner orphan detection

    @Test func orphanedIDs_flagsUnreferencedAttachments() {
        let used = UUID(); let orphan = UUID()
        let contents = [
            "Note one ![](attachment://\(used.uuidString))",
            "Note two with no images",
        ]
        let orphans = AttachmentUsageScanner.orphanedIDs(candidates: [used, orphan], contents: contents)
        #expect(orphans == [orphan])
    }

    @Test func referencedIDs_acrossContents_isUnion() {
        let a = UUID(); let b = UUID()
        let refs = AttachmentUsageScanner.referencedIDs(inContents: [
            "![](attachment://\(a.uuidString))",
            "![](attachment://\(b.uuidString))",
        ])
        #expect(refs == Set([a, b]))
    }
}
