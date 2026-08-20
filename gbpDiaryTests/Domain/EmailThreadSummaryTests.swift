import Foundation
import Testing
@testable import gbpDiary

struct EmailThreadSummaryTests {
    private func line(_ sent: Bool, _ time: String, _ summary: String) -> ThreadMessageLine {
        ThreadMessageLine(directionIsSent: sent, time: time, summary: summary)
    }

    @Test func prompt_embedsDirectionsSummariesAndSharedVoice() {
        let prompt = EmailThreadSummaryPrompt.build(
            subject: "ADACS proposal",
            participants: ["Suzanne", "you"],
            messages: [line(false, "09:14", "Suzanne asked to meet Tuesday."),
                       line(true, "10:02", "You proposed 2pm.")])
        #expect(prompt.contains("Subject: ADACS proposal"))
        #expect(prompt.contains("Participants: Suzanne, you"))
        #expect(prompt.contains("(received 09:14) Suzanne asked to meet Tuesday."))
        #expect(prompt.contains("(sent 10:02) You proposed 2pm."))
        // The shared voice is folded into the instructions.
        #expect(EmailThreadSummaryPrompt.instructions.contains("\"you\""))
        #expect(EmailThreadSummaryPrompt.instructions.lowercased().contains("simple past"))
    }

    @Test func promptVersion_foldsSharedStyleVersion() {
        #expect(EmailThreadSummaryPrompt.promptVersion == 1 + AISummaryStyle.version)
    }

    @Test func fingerprint_changesOnMemberOrVersionChange() {
        let a = UUID(); let b = UUID()
        let base = EmailThreadSummaryFingerprint.make([(a, 3), (b, 3)])
        #expect(base == EmailThreadSummaryFingerprint.make([(b, 3), (a, 3)]))   // order-independent
        #expect(base != EmailThreadSummaryFingerprint.make([(a, 3)]))          // member left
        #expect(base != EmailThreadSummaryFingerprint.make([(a, 3), (b, 4)]))  // a member re-summarised
    }

    @Test func needsSummary_trueWhenMissingStaleOrChanged_falseWhenCurrent() {
        let fp = "fp-current"
        let v = EmailThreadSummaryPrompt.promptVersion
        // Missing record.
        #expect(EmailThreadSummaryPlanning.needsSummary(state: nil, storedFingerprint: nil, fingerprint: fp,
                                                        storedVersion: -1) == true)
        // Done + matching + current → no.
        #expect(EmailThreadSummaryPlanning.needsSummary(state: .done, storedFingerprint: fp, fingerprint: fp,
                                                        storedVersion: v) == false)
        // Fingerprint changed → yes.
        #expect(EmailThreadSummaryPlanning.needsSummary(state: .done, storedFingerprint: "old", fingerprint: fp,
                                                        storedVersion: v) == true)
        // Stale prompt version → yes.
        #expect(EmailThreadSummaryPlanning.needsSummary(state: .done, storedFingerprint: fp, fingerprint: fp,
                                                        storedVersion: v - 1) == true)
        // Failed but same inputs + current → no (don't hammer a genuine failure).
        #expect(EmailThreadSummaryPlanning.needsSummary(state: .failed, storedFingerprint: fp, fingerprint: fp,
                                                        storedVersion: v) == false)
    }
}
