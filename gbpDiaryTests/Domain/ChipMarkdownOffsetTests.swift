import Foundation
import Testing
@testable import gbpDiary

struct ChipMarkdownOffsetTests {
    // A note "Hi <chip> bye" where the chip's markdown ref is 40 chars long.
    // Display runs: "Hi " (3), chip (display 1 / markdown 40), " bye" (4).
    private let runs = [
        ChipRun(displayLength: 3, markdownLength: 3),
        ChipRun(displayLength: 1, markdownLength: 40),
        ChipRun(displayLength: 4, markdownLength: 4),
    ]

    @Test func offset_atStart_isZero() {
        #expect(ChipMarkdownOffset.markdownOffset(displayLocation: 0, runs: runs) == 0)
    }

    @Test func offset_withinFirstPlainRun_isOneToOne() {
        #expect(ChipMarkdownOffset.markdownOffset(displayLocation: 2, runs: runs) == 2)
    }

    @Test func offset_beforeChip_countsPrecedingText() {
        // Display index 3 = right before the chip → markdown offset 3.
        #expect(ChipMarkdownOffset.markdownOffset(displayLocation: 3, runs: runs) == 3)
    }

    @Test func offset_afterChip_includesFullRefLength() {
        // Display index 4 = just after the 1-char chip → 3 (text) + 40 (ref) = 43.
        #expect(ChipMarkdownOffset.markdownOffset(displayLocation: 4, runs: runs) == 43)
    }

    @Test func offset_withinTrailingText_addsOffsetPastChip() {
        // Display index 6 = 2 chars into " bye" → 3 + 40 + 2 = 45.
        #expect(ChipMarkdownOffset.markdownOffset(displayLocation: 6, runs: runs) == 45)
    }

    @Test func offset_atEnd_isTotalMarkdownLength() {
        // Display length 8 → 3 + 40 + 4 = 47.
        #expect(ChipMarkdownOffset.markdownOffset(displayLocation: 8, runs: runs) == 47)
    }

    @Test func offset_beyondEnd_clampsToTotal() {
        #expect(ChipMarkdownOffset.markdownOffset(displayLocation: 99, runs: runs) == 47)
    }

    @Test func offset_noChips_isIdentity() {
        let plain = [ChipRun(displayLength: 10, markdownLength: 10)]
        #expect(ChipMarkdownOffset.markdownOffset(displayLocation: 5, runs: plain) == 5)
    }

    @Test func offset_twoAdjacentChips() {
        // "<chipA><chipB>" — display 2, markdown 40 + 50 = 90; index 1 is between them → 40.
        let two = [
            ChipRun(displayLength: 1, markdownLength: 40),
            ChipRun(displayLength: 1, markdownLength: 50),
        ]
        #expect(ChipMarkdownOffset.markdownOffset(displayLocation: 1, runs: two) == 40)
        #expect(ChipMarkdownOffset.markdownOffset(displayLocation: 2, runs: two) == 90)
    }
}
