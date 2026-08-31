import Foundation
import Testing
@testable import gbpDiary

struct EmailQuotedHistoryTests {
    @Test func gmailAttribution_keepsOnlyNewestMessage() {
        let body = """
        Thanks, that works for me. See you Tuesday.

        On Mon, 12 Jan 2026 at 10:00, Suzanne Ng <suzanne@x.com> wrote:
        > Can we meet Tuesday to discuss the ADACS proposal?
        > Suzanne
        """
        #expect(EmailQuotedHistory.newestMessage(body) == "Thanks, that works for me. See you Tuesday.")
    }

    @Test func wrappedAttribution_backsUpToTheOnLine() {
        let body = """
        Sounds good.

        On Mon, 12 Jan 2026 at 10:00, Suzanne Ng
        <suzanne@x.com> wrote:
        > earlier text
        """
        #expect(EmailQuotedHistory.newestMessage(body) == "Sounds good.")
    }

    @Test func outlookOriginalMessageDivider_isCut() {
        let body = """
        Approved.

        -----Original Message-----
        From: Suzanne Ng <suzanne@x.com>
        Sent: Monday, 12 January 2026 10:00
        To: Greg Poole <greg@x.com>
        Subject: ADACS
        """
        #expect(EmailQuotedHistory.newestMessage(body) == "Approved.")
    }

    @Test func forwardedMessageBanner_isCut() {
        let body = """
        FYI below.

        ---------- Forwarded message ----------
        From: Nick <nick@x.com>
        Date: Mon, 12 Jan 2026
        To: Greg <greg@x.com>
        """
        #expect(EmailQuotedHistory.newestMessage(body) == "FYI below.")
    }

    @Test func outlookUnderscoreSeparator_isCut() {
        let body = """
        Please review.

        ______________________________
        From: Suzanne Ng
        Sent: Monday, 12 January 2026
        To: Greg Poole
        """
        #expect(EmailQuotedHistory.newestMessage(body) == "Please review.")
    }

    @Test func quotedHeaderBlock_requiresSentAndTo() {
        // A bare "From:" line in prose (no Sent/To nearby) must NOT be treated as a header block.
        let body = "From: the desk of Greg, a quick note about the schedule."
        #expect(EmailQuotedHistory.newestMessage(body) == body)
    }

    @Test func sentenceEndingInWrote_isNotCut() {
        let body = "Here is the summary I wrote: the project is on track and the EoI is submitted."
        #expect(EmailQuotedHistory.newestMessage(body) == body)
    }

    @Test func noBoundary_returnsBodyUnchanged() {
        let body = "Short note with a signature.\n\nSent from my iPhone"
        #expect(EmailQuotedHistory.newestMessage(body) == body)
    }

    @Test func bodyQuotedFromStart_returnsUnchanged() {
        // If the very first line is already the attribution (nothing above it), keep the whole body.
        let body = """
        On Mon, 12 Jan 2026 at 10:00, Suzanne <suzanne@x.com> wrote:
        > the whole thing is quoted
        """
        #expect(EmailQuotedHistory.newestMessage(body) == body)
    }

    @Test func emptyBody_isEmpty() {
        #expect(EmailQuotedHistory.newestMessage("   \n  ") == "")
    }
}
