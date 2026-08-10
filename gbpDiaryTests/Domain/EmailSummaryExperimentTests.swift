import Testing
@testable import gbpDiary

@Suite("Email summary experiments")
struct EmailSummaryExperimentTests {
    @Test func adoption_trimsAndMarksSummaryDoneAtCurrentVersion() {
        let values = EmailSummaryAdoption.values(for: "  Please send the draft by Friday.  ", promptVersion: 7)
        #expect(values?.summary == "Please send the draft by Friday.")
        #expect(values?.state == EmailSummaryState.done.rawValue)
        #expect(values?.promptVersion == 7)
    }

    @Test func adoption_rejectsBlankSummary() {
        #expect(EmailSummaryAdoption.values(for: "  \n ") == nil)
    }
}
