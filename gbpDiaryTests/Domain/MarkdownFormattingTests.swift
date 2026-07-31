import Testing
import Foundation
@testable import gbpDiary

@Suite("MarkdownFormatting")
struct MarkdownFormattingTests {
    private func range(_ loc: Int, _ len: Int) -> NSRange { NSRange(location: loc, length: len) }

    // MARK: - Inline wrap (bold/italic/code)

    @Test func bold_wrapsSelection_keepsItSelected() {
        let r = MarkdownFormatting.apply(.bold, to: "hello world", selection: range(0, 5))
        #expect(r.text == "**hello** world")
        #expect(r.selection == range(2, 5))   // "hello" still selected, inside the markers
    }

    @Test func bold_emptySelection_placesCaretBetweenMarkers() {
        let r = MarkdownFormatting.apply(.bold, to: "ab", selection: range(1, 0))
        #expect(r.text == "a****b")
        #expect(r.selection == range(3, 0))   // caret between the ** pairs
    }

    @Test func bold_togglesOffWhenMarkersSurroundSelection() {
        // "**hello** world", "hello" selected (inside markers) → unwrap
        let r = MarkdownFormatting.apply(.bold, to: "**hello** world", selection: range(2, 5))
        #expect(r.text == "hello world")
        #expect(r.selection == range(0, 5))
    }

    @Test func bold_togglesOffWhenSelectionIncludesMarkers() {
        let r = MarkdownFormatting.apply(.bold, to: "**hello** world", selection: range(0, 9))
        #expect(r.text == "hello world")
        #expect(r.selection == range(0, 5))
    }

    @Test func italic_usesSingleAsterisk() {
        let r = MarkdownFormatting.apply(.italic, to: "hi", selection: range(0, 2))
        #expect(r.text == "*hi*")
    }

    @Test func inlineCode_usesBacktick() {
        let r = MarkdownFormatting.apply(.inlineCode, to: "x", selection: range(0, 1))
        #expect(r.text == "`x`")
    }

    // MARK: - Headings

    @Test func heading_addsMarkerToLine() {
        let r = MarkdownFormatting.apply(.heading(2), to: "Agenda", selection: range(0, 0))
        #expect(r.text == "## Agenda")
    }

    @Test func heading_sameLevelTogglesOff() {
        let r = MarkdownFormatting.apply(.heading(2), to: "## Agenda", selection: range(0, 0))
        #expect(r.text == "Agenda")
    }

    @Test func heading_replacesDifferentLevel() {
        let r = MarkdownFormatting.apply(.heading(1), to: "### Agenda", selection: range(0, 0))
        #expect(r.text == "# Agenda")
    }

    // MARK: - Line prefixes

    @Test func bulletList_prefixesEveryLineInSelection() {
        let text = "one\ntwo\nthree"
        let r = MarkdownFormatting.apply(.bulletList, to: text, selection: range(0, text.count))
        #expect(r.text == "- one\n- two\n- three")
    }

    @Test func bulletList_togglesOffWhenAllPrefixed() {
        let text = "- one\n- two"
        let r = MarkdownFormatting.apply(.bulletList, to: text, selection: range(0, (text as NSString).length))
        #expect(r.text == "one\ntwo")
    }

    @Test func checkbox_prefixesLine() {
        let r = MarkdownFormatting.apply(.checkbox, to: "do it", selection: range(0, 0))
        #expect(r.text == "- [ ] do it")
    }

    @Test func quote_prefixesLine() {
        let r = MarkdownFormatting.apply(.quote, to: "said", selection: range(0, 0))
        #expect(r.text == "> said")
    }

    @Test func numberedList_renumbersSequentially() {
        let text = "a\nb\nc"
        let r = MarkdownFormatting.apply(.numberedList, to: text, selection: range(0, (text as NSString).length))
        #expect(r.text == "1. a\n2. b\n3. c")
    }

    @Test func numberedList_togglesOff() {
        let text = "1. a\n2. b"
        let r = MarkdownFormatting.apply(.numberedList, to: text, selection: range(0, (text as NSString).length))
        #expect(r.text == "a\nb")
    }

    // MARK: - Block inserts

    @Test func codeBlock_insertsFencedBlockWithSeparation() {
        let r = MarkdownFormatting.apply(.codeBlock, to: "text", selection: range(4, 0))
        #expect(r.text == "text\n\n```\n\n```")
        #expect(r.selection.length == ("```\n\n```" as NSString).length)
    }

    @Test func table_insertsSkeletonAtCaret() {
        let r = MarkdownFormatting.apply(.table, to: "", selection: range(0, 0))
        #expect(r.text == MarkdownFormatting.tableSkeleton)
    }

    @Test func table_separatesFromSurroundingText() {
        let r = MarkdownFormatting.apply(.table, to: "before", selection: range(6, 0))
        #expect(r.text == "before\n\n" + MarkdownFormatting.tableSkeleton)
    }

    // MARK: - Return-in-list continuation

    @Test func returnInList_bullet_startsNewBullet() {
        let text = "- one"
        let r = MarkdownFormatting.returnInList(text: text, selection: range((text as NSString).length, 0))
        #expect(r?.text == "- one\n- ")
        #expect(r?.selection == range(("- one\n- " as NSString).length, 0))
    }

    @Test func returnInList_preservesIndentAndBulletChar() {
        let text = "  * item"
        let r = MarkdownFormatting.returnInList(text: text, selection: range((text as NSString).length, 0))
        #expect(r?.text == "  * item\n  * ")
    }

    @Test func returnInList_ordered_incrementsNumber() {
        let text = "1. first\n2. second"
        let r = MarkdownFormatting.returnInList(text: text, selection: range((text as NSString).length, 0))
        #expect(r?.text == "1. first\n2. second\n3. ")
    }

    @Test func returnInList_checkbox_startsUncheckedItem() {
        let text = "- [x] done"
        let r = MarkdownFormatting.returnInList(text: text, selection: range((text as NSString).length, 0))
        #expect(r?.text == "- [x] done\n- [ ] ")
    }

    @Test func returnInList_emptyBullet_endsList() {
        let text = "- one\n- "
        let r = MarkdownFormatting.returnInList(text: text, selection: range((text as NSString).length, 0))
        #expect(r?.text == "- one\n")
        #expect(r?.selection == range(("- one\n" as NSString).length, 0))
    }

    @Test func returnInList_emptyIndentedBullet_removesIndentAndMarker() {
        let text = "  - "
        let r = MarkdownFormatting.returnInList(text: text, selection: range((text as NSString).length, 0))
        #expect(r?.text == "")
    }

    @Test func returnInList_midItem_splitsOntoNewMarker() {
        // caret after "one" in "- oneTWO" → new bullet carries "TWO"
        let text = "- oneTWO"
        let r = MarkdownFormatting.returnInList(text: text, selection: range(5, 0))
        #expect(r?.text == "- one\n- TWO")
    }

    @Test func returnInList_nonListLine_returnsNil() {
        #expect(MarkdownFormatting.returnInList(text: "plain text", selection: range(10, 0)) == nil)
    }

    @Test func returnInList_withSelection_returnsNil() {
        #expect(MarkdownFormatting.returnInList(text: "- one", selection: range(0, 3)) == nil)
    }

    @Test func returnInList_quote_continuesQuote() {
        let text = "> quoted"
        let r = MarkdownFormatting.returnInList(text: text, selection: range((text as NSString).length, 0))
        #expect(r?.text == "> quoted\n> ")
    }

    @Test func returnInList_emptyQuote_endsQuote() {
        let text = "> quoted\n> "
        let r = MarkdownFormatting.returnInList(text: text, selection: range((text as NSString).length, 0))
        #expect(r?.text == "> quoted\n")
    }

    // MARK: - Insert on a new line

    @Test func insertOnNewLine_emptyText_insertsInPlace() {
        let r = MarkdownFormatting.insertOnNewLine(text: "", selection: range(0, 0), insert: "**Action GP: x**")
        #expect(r.text == "**Action GP: x**")
    }

    @Test func insertOnNewLine_plainLine_startsNewLine() {
        let r = MarkdownFormatting.insertOnNewLine(text: "Notes", selection: range(2, 0), insert: "X")
        #expect(r.text == "Notes\nX")
    }

    @Test func insertOnNewLine_bulletLine_continuesBullet() {
        let r = MarkdownFormatting.insertOnNewLine(text: "- item", selection: range(3, 0), insert: "X")
        #expect(r.text == "- item\n- X")
    }

    @Test func insertOnNewLine_indentedBullet_preservesIndentAndMarker() {
        let r = MarkdownFormatting.insertOnNewLine(text: "    - item", selection: range(6, 0), insert: "X")
        #expect(r.text == "    - item\n    - X")
    }

    // MARK: - Indent / outdent (quantised to 4 spaces, any line, block-aware)

    @Test func indentLines_caret_addsFourSpacesAndShiftsCaret() {
        let text = "- item"
        let r = MarkdownFormatting.indentLines(text: text, selection: range(2, 0), outdent: false)
        #expect(r?.text == "    - item")
        #expect(r?.selection == range(6, 0))   // caret shifted right by the four-space indent
    }

    @Test func indentLines_worksRegardlessOfCursorPosition() {
        // caret at end of the line still indents the whole line
        let text = "- item"
        let r = MarkdownFormatting.indentLines(text: text, selection: range(6, 0), outdent: false)
        #expect(r?.text == "    - item")
    }

    @Test func indentLines_quantisesPartialIndentUpToNextMultiple() {
        // 2 leading spaces → next multiple of 4 is 4 → add 2
        let r = MarkdownFormatting.indentLines(text: "  - item", selection: range(4, 0), outdent: false)
        #expect(r?.text == "    - item")
    }

    @Test func indentLines_outdentToPreviousMultiple() {
        // 4 spaces → previous multiple is 0
        let r = MarkdownFormatting.indentLines(text: "    - item", selection: range(6, 0), outdent: true)
        #expect(r?.text == "- item")
        #expect(r?.selection == range(2, 0))
    }

    @Test func indentLines_outdentPartialToPreviousMultiple() {
        // 6 spaces → previous multiple of 4 is 4 → remove 2
        let r = MarkdownFormatting.indentLines(text: "      x", selection: range(0, 0), outdent: true)
        #expect(r?.text == "    x")
    }

    @Test func indentLines_appliesToAnyLine_notJustLists() {
        let r = MarkdownFormatting.indentLines(text: "plain", selection: range(2, 0), outdent: false)
        #expect(r?.text == "    plain")
    }

    @Test func indentLines_outdentAtColumnZero_returnsNil() {
        #expect(MarkdownFormatting.indentLines(text: "- item", selection: range(2, 0), outdent: true) == nil)
    }

    @Test func indentLines_shiftsNestedChildBlockWithParent() {
        // Indenting the parent also indents its deeper-indented children by the same delta.
        let text = "- parent\n    - child\n        - grand\n- sibling"
        let r = MarkdownFormatting.indentLines(text: text, selection: range(0, 0), outdent: false)
        #expect(r?.text == "    - parent\n        - child\n            - grand\n- sibling")
    }

    @Test func indentLines_multiLineSelection_indentsBlockUniformly() {
        let text = "- a\n- b"
        let r = MarkdownFormatting.indentLines(text: text, selection: range(0, (text as NSString).length), outdent: false)
        #expect(r?.text == "    - a\n    - b")
    }

    // MARK: - Backspace at marker

    @Test func backspaceInList_atMarkerNoIndent_clearsMarker() {
        // caret right after "- " (location 2)
        let r = MarkdownFormatting.backspaceInList(text: "- item", selection: range(2, 0))
        #expect(r?.text == "item")
        #expect(r?.selection == range(0, 0))
    }

    @Test func backspaceInList_atMarkerIndented_outdentsOneLevel() {
        // "  - item", caret after marker at location 4
        let r = MarkdownFormatting.backspaceInList(text: "  - item", selection: range(4, 0))
        #expect(r?.text == "- item")
        #expect(r?.selection == range(2, 0))
    }

    @Test func backspaceInList_notAtMarkerBoundary_returnsNil() {
        // caret mid-content
        #expect(MarkdownFormatting.backspaceInList(text: "- item", selection: range(4, 0)) == nil)
    }

    @Test func backspaceInList_nonListLine_returnsNil() {
        #expect(MarkdownFormatting.backspaceInList(text: "plain", selection: range(3, 0)) == nil)
    }

    @Test func backspaceInList_checkboxMarker_clears() {
        // "- [ ] task", caret at 6 (after "- [ ] ")
        let r = MarkdownFormatting.backspaceInList(text: "- [ ] task", selection: range(6, 0))
        #expect(r?.text == "task")
    }
}
