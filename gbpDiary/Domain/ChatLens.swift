import Foundation

// Which deterministic "lens" a Chat question routes to. Lenses assemble facts in the app and (at most)
// let the model phrase them, so they are failure-proof (the app can always answer). The open box is the
// existing best-effort retrieval synthesis.
nonisolated enum ChatLens: Equatable, Sendable {
    case timeReport      // "how much/how many hours/days/weeks on [each] project [period]" — app computes
    case activityDigest  // "what did I do / summarise my [period]" — app assembles the real items
    case openBox         // everything else — retrieval + model synthesis (best effort)
}

nonisolated enum ChatLensSelector {
    // Verbs that signal a "what happened" activity recap (as opposed to a factual lookup).
    private static let digestVerbs = ["summar", "recap", "rundown", "what did i do", "what have i done",
                                      "what did i get done", "review of my", "overview of my", "how did my"]

    static func select(scope: ChatQueryScope, question: String) -> ChatLens {
        if scope.wantsTimeTotals { return .timeReport }
        let normalized = question.lowercased()
        if scope.interval != nil, digestVerbs.contains(where: normalized.contains) {
            return .activityDigest
        }
        return .openBox
    }
}
