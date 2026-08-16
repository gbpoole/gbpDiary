import Foundation
import Testing
@testable import gbpDiary

// The Chat evaluation harness: representative questions run end-to-end through ChatAnswerPipeline over a
// fixed corpus (ChatEvalCorpus) with a mock answerer, asserting the DETERMINISTIC stages — parsed scope,
// chosen sources, computed totals, and the assembled prompt. This is the regression signal for every
// future Chat change; the (nondeterministic) model is mocked out. Add a case whenever behaviour changes.
@Suite("Chat eval harness")
@MainActor
struct ChatEvalTests {
    // MARK: mock model

    final class MockChatAnswerer: ChatAnswering, @unchecked Sendable {
        var available = true
        var shouldThrow = false
        private(set) var lastRequest: ChatAnswerRequest?

        var isAvailable: Bool { available }
        var unavailableReason: String? { available ? nil : "unavailable (mock)" }
        func answer(request: ChatAnswerRequest) async throws -> ChatAnswer {
            lastRequest = request
            if shouldThrow { throw ChatAnswerError.modelUnavailable }
            return ChatAnswer(text: "mock answer",
                              citations: request.prompt.sources.map(\.chunk.source),
                              summaryCandidates: [])
        }
    }

    // A resolver returning a fixed scope, to prove the pipeline delegates intent to the injected resolver.
    struct StubScopeResolver: ChatScopeResolving {
        let scope: ChatQueryScope
        func resolve(question: String, history: [ChatHistoryMessage], knownProjectNames: [String],
                     now: Date, calendar: Calendar) async -> ChatQueryScope { scope }
    }

    private func run(_ fx: ChatEvalCorpus.Fixture, _ question: String,
                     history: [ChatHistoryMessage] = [], priorSources: [ChatSourceReference] = [],
                     answerer: any ChatAnswering = MockChatAnswerer(),
                     scopeResolver: any ChatScopeResolving = HeuristicScopeResolver()) async -> ChatPipelineResult {
        let input = ChatAnswerPipeline.Input(
            question: question, history: history, priorSources: priorSources,
            knownProjectNames: ChatEvalCorpus.knownProjectNames,
            now: ChatEvalCorpus.now, calendar: ChatEvalCorpus.calendar)
        return await ChatAnswerPipeline().run(input, retrieve: { fx.retrieve($0, $1) },
                                              timeRecords: { fx.timeRecords }, answerer: answerer,
                                              scopeResolver: scopeResolver)
    }

    private func keys(_ result: ChatPipelineResult) -> [ChatSourceKey] {
        result.rankedSources.map(\.chunk.source.key)
    }

    // MARK: scope

    @Test func scope_emailsForProjectInInterval() async {
        let fx = ChatEvalCorpus.build()
        let r = await run(fx, "emails for NODES - 2026B last week")
        #expect(r.scope.kinds == [.email])
        #expect(r.scope.projectName == ChatEvalCorpus.nodes)
        #expect(r.scope.intervalLabel == "last week")
        #expect(!r.scope.wantsTimeTotals)
    }

    // MARK: retrieval must-include / must-exclude

    @Test func retrieval_lastWeekEmails_scopeToProjectAndWindow() async {
        let fx = ChatEvalCorpus.build()
        let r = await run(fx, "emails for NODES - 2026B last week")
        // Only the NODES email dated in last week; other project + out-of-window emails are excluded.
        #expect(keys(r).contains(fx.key("nodesEmailLastWeek", .email)))
        #expect(!keys(r).contains(fx.key("otherEmailLastWeek", .email)))
        #expect(!keys(r).contains(fx.key("nodesEmailThisWeek", .email)))
        #expect(!keys(r).contains(fx.key("nodesEmailFebruary", .email)))
    }

    @Test func retrieval_lastWeek_neverSurfacesFebruaryMeeting() async {
        // The original bug: a "last week" question surfaced a February meeting.
        let fx = ChatEvalCorpus.build()
        let r = await run(fx, "what happened with NODES - 2026B last week")
        #expect(!keys(r).contains(fx.key("febMeeting", .meeting)))
        #expect(keys(r).allSatisfy { $0 != fx.key("mayMeeting", .meeting) })  // May is also out of last-week
    }

    // MARK: time totals

    @Test func totals_computedDeterministicallyOverInterval() async {
        let fx = ChatEvalCorpus.build()
        let r = await run(fx, "how much time did I spend on NODES - 2026B last month")
        #expect(r.scope.wantsTimeTotals)
        #expect(r.computedTotals == "Computed time totals for last month (authoritative — report these exact figures): NODES - 2026B — 1h; Total — 1h")
        #expect(r.prompt?.prompt.contains("Reproduce that block once") == true)
    }

    @Test func totals_notRequested_promptForbidsInventingThem() async {
        let fx = ChatEvalCorpus.build()
        let r = await run(fx, "summarise NODES - 2026B last week")
        #expect(r.computedTotals == nil)
        #expect(r.prompt?.prompt.contains("Do not report or invent any time totals") == true)
    }

    // MARK: follow-up inheritance (the "give me the totals for that as well" bug)

    @Test func followUp_inheritsPriorProjectIntervalAndKind() async {
        let fx = ChatEvalCorpus.build()
        let history = [
            ChatHistoryMessage(role: .user, text: "emails for NODES - 2026B last week"),
            ChatHistoryMessage(role: .assistant, text: "Here are the NODES emails. [S1]"),
        ]
        let r = await run(fx, "give me the time totals for that as well", history: history)
        // The core regression: a back-referencing follow-up inherits the prior project/interval/kind.
        #expect(r.scope.projectName == ChatEvalCorpus.nodes)
        #expect(r.scope.intervalLabel == "last week")
        #expect(r.scope.kinds == [.email])
        #expect(r.scope.wantsTimeTotals)
        // KNOWN GAP surfaced by the harness (Phase 2 candidate): a bare totals follow-up retrieves nothing
        // (its own words have no corpus traction) and short-circuits before reporting the computed totals —
        // back-reference follow-ups should expand the retrieval query with the prior question like
        // transformations do. Pinned here so a future fix is a deliberate, visible change.
        if case .noResults = r.outcome {} else { Issue.record("expected current noResults behaviour for bare follow-up") }
    }

    // MARK: synthesis prompt shape

    @Test func prompt_defaultsToGroupedBullets() async {
        let fx = ChatEvalCorpus.build()
        let r = await run(fx, "summarise NODES - 2026B last week")
        #expect(r.prompt?.prompt.contains("bulleted list") == true)
        #expect(r.prompt?.prompt.contains("group your answer by project") == true)
    }

    // MARK: outcomes

    @Test func capability_shortCircuitsBeforeRetrieval() async {
        let fx = ChatEvalCorpus.build()
        let r = await run(fx, "what can you do")
        if case .capability = r.outcome {} else { Issue.record("expected capability outcome") }
        #expect(r.rankedSources.isEmpty)
    }

    @Test func noResults_whenIntervalWindowIsEmpty() async {
        let fx = ChatEvalCorpus.build()
        let r = await run(fx, "meetings for NODES - 2026B today")   // no meeting today
        if case .noResults = r.outcome {} else { Issue.record("expected noResults outcome") }
    }

    @Test func unavailableModel_returnsSourcesNotAnswer() async {
        let fx = ChatEvalCorpus.build()
        let mock = MockChatAnswerer(); mock.available = false
        let r = await run(fx, "summarise NODES - 2026B last week", answerer: mock)
        if case .unavailable(_, let sources) = r.outcome { #expect(!sources.isEmpty) }
        else { Issue.record("expected unavailable outcome") }
    }

    @Test func generationFailure_degradesToSources() async {
        let fx = ChatEvalCorpus.build()
        let mock = MockChatAnswerer(); mock.shouldThrow = true
        let r = await run(fx, "summarise NODES - 2026B last week", answerer: mock)
        if case .generationFailed(_, let sources) = r.outcome { #expect(!sources.isEmpty) }
        else { Issue.record("expected generationFailed outcome") }
        #expect(r.answerError?.contains("could not be generated") == true)
    }

    @Test func pipeline_usesInjectedScopeResolver() async {
        // The pipeline must take its scope from the resolver (Phase 1 seam), not hardcoded parsing.
        let fx = ChatEvalCorpus.build()
        var forced = ChatQueryScope()
        forced.kinds = [.email]
        forced.projectName = ChatEvalCorpus.nodes
        let r = await run(fx, "anything at all", scopeResolver: StubScopeResolver(scope: forced))
        #expect(r.scope.kinds == [.email])
        #expect(r.scope.projectName == ChatEvalCorpus.nodes)
    }

    @Test func answered_mapsCitationsFromPromptSources() async {
        let fx = ChatEvalCorpus.build()
        let mock = MockChatAnswerer()
        let r = await run(fx, "summarise NODES - 2026B last week", answerer: mock)
        if case .answered(let answer) = r.outcome {
            #expect(!answer.citations.isEmpty)
            #expect(mock.lastRequest?.prompt.sources.isEmpty == false)
        } else { Issue.record("expected answered outcome") }
    }
}
