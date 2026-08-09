import Testing
@testable import gbpDiary

@Suite("FuzzyMatch")
struct FuzzyMatchTests {
    @Test func matches_inOrderSubsequence() {
        #expect(FuzzyMatch.matches("abc", in: "aXbYc"))       // in order, gaps allowed
        #expect(FuzzyMatch.matches("rprt", in: "Report Q3"))
        #expect(!FuzzyMatch.matches("acb", in: "aXbYc"))      // out of order
        #expect(!FuzzyMatch.matches("abcd", in: "abc"))       // query longer / missing char
    }

    @Test func matches_caseInsensitiveAndEmpty() {
        #expect(FuzzyMatch.matches("REP", in: "report"))
        #expect(FuzzyMatch.matches("", in: "anything"))       // empty query matches all
        #expect(!FuzzyMatch.matches("x", in: ""))
    }
}
