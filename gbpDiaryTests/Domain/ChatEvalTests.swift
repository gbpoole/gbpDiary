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
                                              timeLedger: { fx.ledger($0) },
                                              activityProvider: { fx.activity($0) },
                                              answerer: answerer, scopeResolver: scopeResolver)
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
        // A time question routes to the time-report lens: the app RENDERS the answer deterministically
        // (no model), so it's always correct and never degrades.
        let fx = ChatEvalCorpus.build()
        let r = await run(fx, "how much time did I spend on NODES - 2026B last month")
        #expect(r.scope.wantsTimeTotals)
        guard case .answered(let answer) = r.outcome else { Issue.record("expected answered"); return }
        #expect(answer.text.contains("NODES - 2026B"))
        #expect(answer.text.contains("1h"))
        #expect(answer.text.contains("last month"))
        #expect(r.prompt == nil)   // deterministic — the model was not consulted
    }

    @Test func timeReport_allTime_perProject_neverDegrades() async {
        // The reported bug: "how many weeks did I work on each project" used to return the degraded
        // "could not generate a grounded answer". Now it is a deterministic per-project report.
        let fx = ChatEvalCorpus.build()
        let r = await run(fx, "how many weeks did I work on each project")
        #expect(r.scope.wantsTimeTotals)
        guard case .answered(let answer) = r.outcome else { Issue.record("expected answered, got \(r.outcome)"); return }
        #expect(answer.text.contains("NODES - 2026B"))
        #expect(answer.text.contains("week"))            // distinct-weeks-active phrasing
    }

    @Test func totals_notRequested_promptForbidsInventingThem() async {
        // An open-box question (no time intent, no interval/digest verb) still forbids inventing totals.
        let fx = ChatEvalCorpus.build()
        let r = await run(fx, "tell me about NODES - 2026B")
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
        // Now fixed (was the "noResults" gap): the time-report lens answers deterministically regardless of
        // retrieval — even when there's no logged time in the inherited window it reports 0, never degrading.
        guard case .answered(let answer) = r.outcome else { Issue.record("expected answered, got \(r.outcome)"); return }
        #expect(answer.text.contains("last week"))
    }

    @Test func selfContainedQuestion_withPronoun_doesNotInheritPriorProject() async {
        // Reported bug: after a NODES question, "…the weeks I spent on THEM" was wrongly scoped to NODES.
        // "them" refers to "projects" in the sentence — the self-contained question must cover all projects.
        let fx = ChatEvalCorpus.build()
        let history = [
            ChatHistoryMessage(role: .user, text: "what happened with NODES - 2026B last week"),
            ChatHistoryMessage(role: .assistant, text: "Here's the NODES recap. [S1]"),
        ]
        let r = await run(fx, "give me a list of projects I worked on last week and the weeks I spent on them",
                          history: history)
        #expect(r.scope.projectName == nil)          // NOT inherited from the prior NODES turn
        #expect(r.scope.wantsTimeTotals)
        guard case .answered(let answer) = r.outcome else { Issue.record("expected answered"); return }
        #expect(answer.text.contains("NODES - 2026B"))
        #expect(answer.text.contains("Other Project"))   // several projects, not just NODES
    }

    // MARK: synthesis prompt shape

    @Test func prompt_defaultsToGroupedBullets() async {
        let fx = ChatEvalCorpus.build()
        let r = await run(fx, "tell me about NODES - 2026B")   // open box
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
        let r = await run(fx, "tell me about NODES - 2026B", answerer: mock)
        if case .unavailable(_, let sources) = r.outcome { #expect(!sources.isEmpty) }
        else { Issue.record("expected unavailable outcome") }
    }

    @Test func generationFailure_degradesToSources() async {
        let fx = ChatEvalCorpus.build()
        let mock = MockChatAnswerer(); mock.shouldThrow = true
        let r = await run(fx, "tell me about NODES - 2026B", answerer: mock)
        if case .generationFailed(_, let sources) = r.outcome { #expect(!sources.isEmpty) }
        else { Issue.record("expected generationFailed outcome") }
        #expect(r.answerError?.contains("could not be generated") == true)
    }

    // MARK: activity digest + weekend fidelity

    @Test func digest_summariseLastWeek_foldsWeekendAndInventsNothing() async {
        // Model unavailable → the app's deterministic digest IS the answer (proves it's weekend-safe).
        let fx = ChatEvalCorpus.build()
        let mock = MockChatAnswerer(); mock.available = false
        let r = await run(fx, "give me a summary of my last week", answerer: mock)
        guard case .answered(let answer) = r.outcome else { Issue.record("expected answered, got \(r.outcome)"); return }
        #expect(answer.text.contains("Fri 12 Jun"))        // the Saturday meeting folded to Friday
        #expect(answer.text.contains("NODES sprint push"))
        #expect(!answer.text.contains("Sat"))              // never a weekend day
        #expect(!answer.text.contains("13 Jun"))           // the raw Saturday date is gone
    }

    @Test func digest_handsModelAWeekendFreeBlock() async {
        let fx = ChatEvalCorpus.build()
        let r = await run(fx, "summarise my last week")    // model available (default mock)
        guard case .answered = r.outcome else { Issue.record("expected answered"); return }
        #expect(r.prompt?.prompt.contains("Rewrite the following") == true)
        #expect(r.prompt?.prompt.contains("Fri 12 Jun") == true)
        #expect(r.prompt?.prompt.contains("13 Jun") == false)   // no weekend date reaches the model
    }

    @Test func corpus_foldsWeekendMeetingDateToWeekday() {
        let fx = ChatEvalCorpus.build()
        let doc = fx.document("satMeeting", .meeting)
        #expect(doc?.markdown.contains("Fri 12 Jun 2026") == true)
        #expect(doc?.markdown.contains("13 Jun") == false)
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
        let r = await run(fx, "tell me about NODES - 2026B", answerer: mock)
        if case .answered(let answer) = r.outcome {
            #expect(!answer.citations.isEmpty)
            #expect(mock.lastRequest?.prompt.sources.isEmpty == false)
        } else { Issue.record("expected answered outcome") }
    }
}
