import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct NoteLinkRefTests {

    // MARK: - NoteLinkRef url/markdown/parse round-trips

    @Test func url_and_id_roundTrip() {
        let id = UUID()
        let url = NoteLinkRef.url(for: id)
        #expect(url == "note://\(id.uuidString)")
        #expect(NoteLinkRef.id(fromURL: url) == id)
    }

    @Test func id_fromURL_rejectsNonNoteSchemes() {
        #expect(NoteLinkRef.id(fromURL: "https://example.com/\(UUID().uuidString)") == nil)
        #expect(NoteLinkRef.id(fromURL: "attachment://\(UUID().uuidString)") == nil)
        #expect(NoteLinkRef.id(fromURL: "note://not-a-uuid") == nil)
    }

    @Test func markdown_embedsTitleAndRef() {
        let id = UUID()
        let md = NoteLinkRef.markdown(for: id, displayName: "Research Ideas")
        #expect(md == "[Research Ideas](note://\(id.uuidString))")
    }

    @Test func markdown_sanitizesClosingBracketInTitle() {
        let id = UUID()
        let md = NoteLinkRef.markdown(for: id, displayName: "a]b")
        // The closing bracket must not break the link-text span.
        #expect(!md.contains("a]b"))
        #expect(NoteLinkRef.referencedIDs(in: md) == [id])
    }

    // MARK: - referencedIDs extraction

    @Test func referencedIDs_extractsAllInOrder() {
        let a = UUID(); let b = UUID()
        let markdown = "See [A](note://\(a.uuidString)) and later [B](note://\(b.uuidString))."
        #expect(NoteLinkRef.referencedIDs(in: markdown) == [a, b])
    }

    @Test func referencedIDs_ignoresImageAndPlainLinks() {
        let noteID = UUID(); let imgID = UUID()
        let markdown = """
        A plain [link](https://example.com), an image ![pic](attachment://\(imgID.uuidString)),
        and a note [Target](note://\(noteID.uuidString)).
        """
        #expect(NoteLinkRef.referencedIDs(in: markdown) == [noteID])
    }
}
