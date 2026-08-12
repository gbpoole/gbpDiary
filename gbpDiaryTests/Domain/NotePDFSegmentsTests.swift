import Foundation
import Testing
@testable import gbpDiary

struct NotePDFSegmentsTests {
    private func ref(_ id: UUID) -> String { AttachmentRef.markdown(for: id, displayName: "pic") }

    @Test func noImages_isSingleTextSegment() {
        #expect(NotePDFSegments.segments(from: "just text") == [.text("just text")])
    }

    @Test func emptyMarkdown_isEmpty() {
        #expect(NotePDFSegments.segments(from: "") == [])
        #expect(NotePDFSegments.segments(from: "   \n  ") == [])
    }

    @Test func oneImage_splitsTextImageText() {
        let id = UUID()
        let md = "before\n\n\(ref(id))\n\nafter"
        let segs = NotePDFSegments.segments(from: md)
        #expect(segs.count == 3)
        #expect(segs.first == .text("before\n\n"))
        #expect(segs[1] == .image(id))
        if case .text(let t) = segs[2] { #expect(t.contains("after")) } else { Issue.record("expected trailing text") }
    }

    @Test func imageOnly_isSingleImageSegment() {
        let id = UUID()
        #expect(NotePDFSegments.segments(from: ref(id)) == [.image(id)])
    }

    @Test func multipleImages_preserveOrder() {
        let a = UUID(), b = UUID()
        let md = "\(ref(a))\n\ntext\n\n\(ref(b))"
        let segs = NotePDFSegments.segments(from: md)
        #expect(segs.first == .image(a))
        #expect(segs.last == .image(b))
        #expect(segs.contains { if case .text(let t) = $0 { return t.contains("text") } else { return false } })
    }
}
