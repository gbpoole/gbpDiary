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
             timeLedger: (Range<Date>?) -> LedgerResult,
             activityProvider: (Range<Date>) -> ChatActivityDigest = { _ in ChatActivityDigest(items: []) },
             answerer: any ChatAnswering,
             scopeResolver: any ChatScopeResolving = HeuristicScopeResolver()) async -> ChatPipelineResult {
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

        // 2. FAST routing scope from the deterministic heuristic only — no model call — so we can pick the
        //    lens before paying for retrieval or the scope model call. (A back-referencing follow-up still
        //    inherits the prior turn's project/interval/kind here.)
        let routingScope = isTransformation
            ? ChatQueryScope()
            : await HeuristicScopeResolver().resolve(question: question, history: history,
                                                     knownProjectNames: input.knownProjectNames,
                                                     now: input.now, calendar: input.calendar)
        let lens = isTransformation ? .openBox : ChatLensSelector.select(scope: routingScope, question: question)

        // 3a. Time-report lens — the app RENDERS the answer from the canonical ledger. NO model, NO
        //     retrieval → effectively instant, and it never degrades.
        if lens == .timeReport {
            let scope = routingScope
            let totals = ChatTimeTotals.from(ledger: timeLedger(scope.interval), projectName: scope.projectName)
            let text: String
            if totals.isEmpty {
                let overall = ChatTimeTotals.from(ledger: timeLedger(nil), projectName: scope.projectName).overall
                text = ChatTimeTotals.emptyReport(interval: scope.interval, intervalLabel: scope.intervalLabel,
                                                  projectName: scope.projectName, overallHours: overall,
                                                  calendar: input.calendar)
            } else {
                text = totals.report(intervalLabel: scope.intervalLabel, projectName: scope.projectName)
            }
            return ChatPipelineResult(
                scope: scope, retrievalError: nil, rankedSources: [],
                computedTotals: totals.authoritativeBlock(intervalLabel: scope.intervalLabel ?? "all time"),
                prompt: nil, outcome: .answered(ChatAnswer(text: text, citations: [], summaryCandidates: [])))
        }

        // 3b. Activity-digest lens — the app assembles the window's REAL items (weekend-folded); the model
        //     may only rephrase that block, and if it's unavailable/misbehaves the app's rendering is the
        //     answer. NO retrieval; it can never invent a day that didn't happen, and never degrades.
        if lens == .activityDigest, let interval = routingScope.interval {
            let scope = routingScope
            let digest = activityProvider(interval)
            guard !digest.isEmpty else {
                return ChatPipelineResult(scope: scope, retrievalError: nil, rankedSources: [],
                    computedTotals: nil, prompt: nil,
                    outcome: .answered(ChatAnswer(
                        text: "You have no recorded activity for \(scope.intervalLabel ?? "that period").",
                        citations: [], summaryCandidates: [])))
            }
            let block = digest.render(calendar: input.calendar)
            if answerer.isAvailable {
                let bundle = ChatPromptBundle(
                    prompt: ChatActivityDigestBuilder.phrasingPrompt(block: block, intervalLabel: scope.intervalLabel),
                    sources: [], requiresCitation: false)
                if let answer = try? await answerer.answer(request: ChatAnswerRequest(prompt: bundle, fallbackCitations: digest.sources)) {
                    return ChatPipelineResult(scope: scope, retrievalError: nil, rankedSources: [],
                        computedTotals: nil, prompt: bundle,
                        outcome: .answered(ChatAnswer(text: answer.text, citations: digest.sources, summaryCandidates: [])))
                }
            }
            return ChatPipelineResult(scope: scope, retrievalError: nil, rankedSources: [],
                computedTotals: nil, prompt: nil,
                outcome: .answered(ChatAnswer(text: block, citations: digest.sources, summaryCandidates: [])))
        }

        // 3c. Open box — the ONLY path that needs the (model-refined) scope AND retrieval.
        let scope = isTransformation
            ? ChatQueryScope()
            : await scopeResolver.resolve(question: question, history: history,
                                          knownProjectNames: input.knownProjectNames,
                                          now: input.now, calendar: input.calendar)
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
        let prompt = ChatPromptBuilder.build(
            question: question, rankedChunks: ranked, history: history,
            allowsUncitedTransformation: isTransformation, wantsOverview: scope.wantsOverview,
            computedTotals: nil,
            // A grouped summary needn't cite every point inline; the ranked sources are shown as links.
            requiresCitation: isTransformation ? nil : false)
        do {
            let answer = try await answerer.answer(request: ChatAnswerRequest(
                prompt: prompt, fallbackCitations: isTransformation ? priorSources : fallbackSources))
            return ChatPipelineResult(scope: scope, retrievalError: ranking.error, rankedSources: ranked,
                                      computedTotals: nil, prompt: prompt, outcome: .answered(answer))
        } catch {
            return ChatPipelineResult(
                scope: scope, retrievalError: ranking.error, rankedSources: ranked,
                computedTotals: nil, prompt: prompt,
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
