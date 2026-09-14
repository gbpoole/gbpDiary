import Testing
import Foundation
@testable import gbpDiary

@Suite("CaptureURL")
struct CaptureURLTests {
    private func parse(_ s: String) -> CaptureURL.Request? {
        guard let url = URL(string: s) else { return nil }
        return CaptureURL.parse(url)
    }

    @Test func parsesWebCapture() {
        let r = parse("gbpdiary://task?kind=web&url=https://example.com&title=Read%20this")
        #expect(r?.kind == .web)
        #expect(r?.url == "https://example.com")
        #expect(r?.title == "Read this")   // percent-decoded
        #expect(r?.mailId == nil)
    }

    @Test func parsesEmailCaptureWithMailId() {
        let r = parse("gbpdiary://task?kind=email&mailId=12345&title=Subj")
        #expect(r?.kind == .email)
        #expect(r?.mailId == "12345")
    }

    @Test func kindDefaultsToOther() {
        #expect(parse("gbpdiary://task?title=Just%20a%20thought")?.kind == .other)
    }

    @Test func unknownKindFallsBackToOther() {
        #expect(parse("gbpdiary://task?kind=carrierpigeon&title=x")?.kind == .other)
    }

    @Test func rejectsWrongScheme() {
        #expect(parse("https://task?title=x") == nil)
    }

    @Test func rejectsNonTaskAction() {
        #expect(parse("gbpdiary://settings?title=x") == nil)
    }

    @Test func rejectsEmptyContent() {
        #expect(parse("gbpdiary://task") == nil)
        #expect(parse("gbpdiary://task?kind=web") == nil)   // kind alone isn't content
    }
}
