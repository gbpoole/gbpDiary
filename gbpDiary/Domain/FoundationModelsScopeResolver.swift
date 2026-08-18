import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// The on-device intent resolver: asks `SystemLanguageModel.default` to fill a small structured spec
// (guided generation), then MERGES it over the deterministic heuristic scope via `ChatQuerySpecMapping`
// so the result can only refine, never regress. Any unavailability/error returns the heuristic scope
// unchanged. Strictly on-device — no network, no Private Cloud Compute.
struct FoundationModelsScopeResolver: ChatScopeResolving {
    var fallback: any ChatScopeResolving = HeuristicScopeResolver()

    func resolve(question: String, history: [ChatHistoryMessage], knownProjectNames: [String],
                 now: Date, calendar: Calendar) async -> ChatQueryScope {
        let heuristic = await fallback.resolve(question: question, history: history,
                                               knownProjectNames: knownProjectNames, now: now, calendar: calendar)
        // Only a bare follow-up may resolve references from the conversation; a self-contained question is
        // resolved standalone so it can't inherit the prior turn's project (e.g. "…the weeks I spent on them").
        let ownScope = ChatQueryScopeParser.parse(question: question, knownProjectNames: knownProjectNames,
                                                  now: now, calendar: calendar)
        let isFollowUp = ownScope.isElliptical && ChatQueryScopeParser.isBackReference(question)
        #if canImport(FoundationModels)
        if #available(macOS 26, *), SystemLanguageModel.default.availability == .available {
            let instructions = """
            You extract the search intent of a workspace question into the given fields. Use only project \
            names from the provided list; if none apply, leave projectName empty. Set projectName ONLY when \
            THIS question focuses on one named project — leave it empty for a question about multiple \
            projects, a list of projects, or "each project". Classify the time period into exactly one of \
            the allowed options. Set the flags only when clearly asked. Resolve references like "that" or \
            "as well" using the recent conversation.
            """
            let session = LanguageModelSession(instructions: instructions)
            let options = GenerationOptions(temperature: 0.0, maximumResponseTokens: 120)
            let prompt = Self.prompt(question: question, history: isFollowUp ? history : [],
                                     knownProjectNames: knownProjectNames)
            if let response = try? await session.respond(to: prompt, generating: ChatQuerySpecDraft.self, options: options) {
                let draft = response.content
                let kinds = draft.kinds.split { $0 == "," || $0 == " " }.map(String.init)
                let period = ChatDatePeriod(rawValue: draft.period.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .none
                return ChatQuerySpecMapping.merge(
                    lmKinds: kinds, lmProjectName: draft.projectName, lmPeriod: period,
                    lmWantsTotals: draft.wantsTimeTotals, lmWantsOverview: draft.wantsOverview,
                    heuristic: heuristic, knownProjectNames: knownProjectNames, now: now, calendar: calendar)
            }
        }
        #endif
        return heuristic
    }

    static func prompt(question: String, history: [ChatHistoryMessage], knownProjectNames: [String]) -> String {
        var parts: [String] = []
        if !history.isEmpty {
            let recent = history.suffix(4)
                .map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
                .joined(separator: "\n")
            parts.append("Recent conversation:\n\(recent)")
        }
        parts.append("Known projects: \(knownProjectNames.isEmpty ? "(none)" : knownProjectNames.joined(separator: "; "))")
        parts.append("Question: \(question)")
        return parts.joined(separator: "\n\n")
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct ChatQuerySpecDraft {
    @Guide(description: "Comma-separated record kinds the question is about, chosen only from: email, task, meeting, note, person, institution, document, project, diary. Empty if unclear.")
    var kinds: String
    @Guide(description: "The single project name from the Known projects list this is about, copied verbatim. Empty for none.")
    var projectName: String
    @Guide(description: "The time period, exactly one of: none, today, yesterday, thisWeek, lastWeek, thisMonth, lastMonth, thisYear, recent.")
    var period: String
    @Guide(description: "true only if the question asks for a total or sum of time or hours.")
    var wantsTimeTotals: Bool
    @Guide(description: "true only if the question asks for an overview, prose, or narrative rather than a bulleted list.")
    var wantsOverview: Bool
}
#endif
