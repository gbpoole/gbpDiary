import Foundation
import Testing
@testable import gbpDiary

struct MarkdownBlankTests {
    @Test func trulyEmpty_isBlank() {
        #expect(MarkdownBlank.isBlank(""))
        #expect(MarkdownBlank.isBlank("   "))
        #expect(MarkdownBlank.isBlank("\n\n"))
    }

    @Test func loneListMarkers_areBlank() {
        #expect(MarkdownBlank.isBlank("- "))          // the FUSE-meeting case
        #expect(MarkdownBlank.isBlank("-"))
        #expect(MarkdownBlank.isBlank("* "))
        #expect(MarkdownBlank.isBlank("+ "))
        #expect(MarkdownBlank.isBlank("1. "))
        #expect(MarkdownBlank.isBlank("2) "))
    }

    @Test func emptyCheckboxAndQuoteAndHeading_areBlank() {
        #expect(MarkdownBlank.isBlank("- [ ]"))
        #expect(MarkdownBlank.isBlank("- [x] "))
        #expect(MarkdownBlank.isBlank("> "))
        #expect(MarkdownBlank.isBlank(">> "))
        #expect(MarkdownBlank.isBlank("# "))
        #expect(MarkdownBlank.isBlank("###### "))
    }

    @Test func multipleEmptyScaffoldLines_areBlank() {
        #expect(MarkdownBlank.isBlank("- \n- \n"))
        #expect(MarkdownBlank.isBlank("> \n\n- "))
    }

    @Test func anyVisibleText_isNotBlank() {
        #expect(!MarkdownBlank.isBlank("- item"))
        #expect(!MarkdownBlank.isBlank("Hello"))
        #expect(!MarkdownBlank.isBlank("# Title"))
        #expect(!MarkdownBlank.isBlank("> quoted text"))
        #expect(!MarkdownBlank.isBlank("- [x] done"))
        #expect(!MarkdownBlank.isBlank("- \nreal note"))   // one empty bullet, then content
    }
}
