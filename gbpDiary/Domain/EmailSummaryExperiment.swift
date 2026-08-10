import Foundation

struct EmailSummaryExperimentRequest: Equatable {
    let context: SummaryContext
    let subject: String
    let body: String
    let experimentalInstructions: String
    let backgroundSources: [ChatPromptSource]
}

protocol EmailSummaryExperimenting {
    var isAvailable: Bool { get }
    func generate(_ request: EmailSummaryExperimentRequest) async throws -> String
}

enum EmailSummaryAdoption {
    struct Values: Equatable {
        let summary: String
        let state: String
        let promptVersion: Int
    }

    static func values(for summary: String,
                       promptVersion: Int = EmailSummaryPrompt.promptVersion) -> Values? {
        let clean = EmailSummaryText.clean(summary)
        guard !clean.isEmpty else { return nil }
        return Values(summary: clean, state: EmailSummaryState.done.rawValue,
                      promptVersion: promptVersion)
    }
}
