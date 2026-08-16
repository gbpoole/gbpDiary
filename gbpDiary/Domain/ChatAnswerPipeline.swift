import Foundation

// The Database-Chat answer orchestration, extracted from `ChatView.answerPendingQuestion` so it can be
// tested without the view or the (nondeterministic) on-device model. It depends only on injected
// abstractions — a `retrieve` closure and a `ChatAnswering` — and every stage of the result is exposed
// so the eval harness can assert on scope, chosen sources, computed totals, and the assembled prompt,
// not just the final text.
//
// This is orchestration, not pure domain math, so it stays main-actor-isolated (the default) and calls
// the already-pure helpers (ChatQueryScopeParser, ChatScopedRanking, ChatTimeTotals, ChatPromptBuilder,
// ChatAnswerAssembly via the answerer). Behaviour must stay identical to the pre-extraction view code.

enum ChatPipelineOutcome: Sendable {
    case capability(String)                                              // canned help answer, no retrieval
    case noResults                                                       // nothing relevant found
    case unavailable(reason: String?, sources: [ChatSourceReference])   // model unavailable; show sources
    case answered(ChatAnswer)                                           // grounded answer
    case generationFailed(message: String, sources: [ChatSourceReference]) // model threw; degrade to sources
}

struct ChatPipelineResult: Sendable {
    var scope: ChatQueryScope
    var retrievalError: String?
    var rankedSources: [ChatRankedChunk]
    var computedTotals: String?
    var prompt: ChatPromptBundle?
    var outcome: ChatPipelineOutcome

    /// The error-banner text the view should show: a generation failure wins, else the retrieval note.
    var answerError: String? {
        if case .generationFailed(let message, _) = outcome { return message }
        return retrievalError
    }
}

struct ChatAnswerPipeline {
    struct Input {
        let question: String
        let history: [ChatHistoryMessage]
        let priorSources: [ChatSourceReference]
        let knownProjectNames: [String]
        var now: Date = Date()
        var calendar: Calendar = .current
    }

    var candidateLimit = 40
    var promptSourceLimit = 10

    func run(_ input: Input,
             retrieve: (String, Int) async -> (chunks: [ChatRankedChunk], error: String?),
             timeRecords: () -> [ChatTimeRecord],
             answerer: any ChatAnswering) async -> ChatPipelineResult {
        let question = input.question

        // 1. Standalone capability/help questions answer immediately, before any retrieval.
        if let capability = ChatCapabilityResponse.answer(for: question) {
            return ChatPipelineResult(scope: ChatQueryScope(), retrievalError: nil, rankedSources: [],
                                      computedTotals: nil, prompt: nil, outcome: .capability(capability))
        }

        let history = input.history
        let isTransformation = ChatFollowUpIntent.isTransformation(question: question, history: history)
        let priorSources = input.priorSources
        let retrievalQuery = ChatFollowUpIntent.retrievalQuery(question: question, history: history)

        // 2. Scope from the user's actual question (not the follow-up-expanded retrieval query); a
        //    back-referencing follow-up inherits the prior question's project/interval/kind.
        var scope = isTransformation
            ? ChatQueryScope()
            : ChatQueryScopeParser.parse(question: question, knownProjectNames: input.knownProjectNames,
                                         now: input.now, calendar: input.calendar)
        if !isTransformation, ChatQueryScopeParser.isBackReference(question),
           let priorQuestion = history.last(where: { $0.role == .user })?.text {
            let priorScope = ChatQueryScopeParser.parse(question: priorQuestion,
                                                        knownProjectNames: input.knownProjectNames,
                                                        now: input.now, calendar: input.calendar)
            scope = scope.inheriting(from: priorScope)
        }

        // 3. Rank a larger candidate set, then hard-restrict to the detected kind/project/interval.
        let ranking = await retrieve(retrievalQuery, candidateLimit)
        let scoped = ChatScopedRanking.apply(ranking.chunks, scope: scope)
        let ranked = Array(scoped.prefix(promptSourceLimit))
        guard !ranked.isEmpty || isTransformation else {
            return ChatPipelineResult(scope: scope, retrievalError: ranking.error, rankedSources: [],
                                      computedTotals: nil, prompt: nil, outcome: .noResults)
        }

        let fallbackSources = Self.unique((isTransformation ? priorSources : []) + ranked.map(\.chunk.source))
        guard answerer.isAvailable else {
            return ChatPipelineResult(scope: scope, retrievalError: ranking.error, rankedSources: ranked,
                                      computedTotals: nil, prompt: nil,
                                      outcome: .unavailable(reason: answerer.unavailableReason, sources: fallbackSources))
        }

        // 4. Deterministic time totals over the requested interval — the app sums; the model must not.
        var computedTotals: String? = nil
        if scope.wantsTimeTotals, let interval = scope.interval, let label = scope.intervalLabel {
            let totals = ChatTimeTotals.compute(records: timeRecords(), interval: interval,
                                                projectName: scope.projectName)
            computedTotals = totals.authoritativeBlock(intervalLabel: label)
                ?? "Computed time totals for \(label) (authoritative): no time was logged in this interval — report 0 hours."
        }

        // 5. Assemble the grounded prompt and call the model.
        let prompt = ChatPromptBuilder.build(
            question: question, rankedChunks: ranked, history: history,
            allowsUncitedTransformation: isTransformation, wantsOverview: scope.wantsOverview,
            computedTotals: computedTotals,
            // A grouped summary needn't cite every point inline; the ranked sources are shown as links.
            requiresCitation: isTransformation ? nil : false)
        do {
            let answer = try await answerer.answer(request: ChatAnswerRequest(
                prompt: prompt, fallbackCitations: isTransformation ? priorSources : fallbackSources))
            return ChatPipelineResult(scope: scope, retrievalError: ranking.error, rankedSources: ranked,
                                      computedTotals: computedTotals, prompt: prompt, outcome: .answered(answer))
        } catch {
            return ChatPipelineResult(
                scope: scope, retrievalError: ranking.error, rankedSources: ranked,
                computedTotals: computedTotals, prompt: prompt,
                outcome: .generationFailed(
                    message: "The on-device answer could not be generated: \(error.localizedDescription)",
                    sources: fallbackSources))
        }
    }

    /// De-duplicate sources by their stable `ChatSourceKey`, preserving order.
    static func unique(_ sources: [ChatSourceReference]) -> [ChatSourceReference] {
        var seen = Set<ChatSourceKey>()
        return sources.filter { seen.insert($0.key).inserted }
    }
}
