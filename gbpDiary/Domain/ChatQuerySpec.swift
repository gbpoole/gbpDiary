import Foundation

// Phase 1 of the Chat reliability strategy: intent understanding moves from brittle keyword/regex parsing
// to the on-device model, but SAFELY — the model's structured output is *merged over* the deterministic
// heuristic scope, so it can only add signal, never regress. The model call lives behind
// `ChatScopeResolving` (see FoundationModelsScopeResolver); this file holds the protocol, the deterministic
// resolver (the always-available fallback), and the pure merge/mapping that both are tested through.

protocol ChatScopeResolving {
    /// Resolve a question (+ recent history, for follow-up reference resolution) into a retrieval scope.
    func resolve(question: String, history: [ChatHistoryMessage], knownProjectNames: [String],
                 now: Date, calendar: Calendar) async -> ChatQueryScope
}

// The deterministic resolver: the existing `ChatQueryScopeParser` + back-reference inheritance. This is
// the fallback whenever the model is unavailable, and it is what the eval harness injects for determinism.
struct HeuristicScopeResolver: ChatScopeResolving {
    func resolve(question: String, history: [ChatHistoryMessage], knownProjectNames: [String],
                 now: Date, calendar: Calendar) async -> ChatQueryScope {
        var scope = ChatQueryScopeParser.parse(question: question, knownProjectNames: knownProjectNames,
                                               now: now, calendar: calendar)
        if ChatQueryScopeParser.isBackReference(question),
           let priorQuestion = history.last(where: { $0.role == .user })?.text {
            let priorScope = ChatQueryScopeParser.parse(question: priorQuestion,
                                                        knownProjectNames: knownProjectNames,
                                                        now: now, calendar: calendar)
            scope = scope.inheriting(from: priorScope)
        }
        return scope
    }
}

// A fixed set of date windows the model classifies into (classification is far more reliable than
// free-form date generation on a small model). `.none` leaves the deterministic date parse in charge.
nonisolated enum ChatDatePeriod: String, CaseIterable, Sendable {
    case none, today, yesterday, thisWeek, lastWeek, thisMonth, lastMonth, thisYear, recent

    func window(now: Date, calendar: Calendar) -> (range: Range<Date>, label: String)? {
        let startOfToday = calendar.startOfDay(for: now)
        func plusDays(_ n: Int, _ d: Date) -> Date { calendar.date(byAdding: .day, value: n, to: d) ?? d }
        switch self {
        case .none: return nil
        case .today: return (startOfToday..<plusDays(1, startOfToday), "today")
        case .yesterday: return (plusDays(-1, startOfToday)..<startOfToday, "yesterday")
        case .thisWeek:
            guard let w = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
            return (w.start..<w.end, "this week")
        case .lastWeek:
            guard let w = calendar.dateInterval(of: .weekOfYear, for: now),
                  let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: w.start) else { return nil }
            return (prev..<w.start, "last week")
        case .thisMonth:
            guard let m = calendar.dateInterval(of: .month, for: now) else { return nil }
            return (m.start..<m.end, "this month")
        case .lastMonth:
            guard let m = calendar.dateInterval(of: .month, for: now),
                  let prev = calendar.date(byAdding: .month, value: -1, to: m.start) else { return nil }
            return (prev..<m.start, "last month")
        case .thisYear:
            guard let y = calendar.dateInterval(of: .year, for: now) else { return nil }
            return (y.start..<y.end, "this year")
        case .recent:
            return (plusDays(-13, startOfToday)..<plusDays(1, startOfToday), "recently")
        }
    }
}

// The pure mapping the model's structured output flows through. Merges the model's fields OVER a
// deterministic `heuristic` scope so the result is always ≥ the heuristic (never a regression): the model
// refines kinds/project/period/flags where confident, the heuristic backstops everything else (including
// "past N weeks" and reference inheritance the enum period can't express).
nonisolated enum ChatQuerySpecMapping {
    static let kindMap: [String: ChatSourceKind] = [
        "email": .email, "task": .task, "meeting": .meeting, "note": .note, "person": .person,
        "institution": .institution, "document": .document, "project": .project, "diary": .day
    ]

    static func resolveKinds(_ raw: [String]) -> Set<ChatSourceKind> {
        Set(raw.compactMap { kindMap[$0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] })
    }

    /// Validate the model's project name against the authoritative known list (exact case-insensitive,
    /// else longest containment either direction). Returns nil rather than ever trusting a hallucinated name.
    static func resolveProject(_ raw: String?, knownProjectNames: [String]) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.lowercased() != "none" else { return nil }
        if let exact = knownProjectNames.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return exact
        }
        let needle = trimmed.lowercased()
        return knownProjectNames
            .filter { let n = $0.lowercased(); return n.contains(needle) || needle.contains(n) }
            .max { $0.count < $1.count }
    }

    static func merge(lmKinds: [String], lmProjectName: String?, lmPeriod: ChatDatePeriod,
                      lmWantsTotals: Bool, lmWantsOverview: Bool,
                      heuristic: ChatQueryScope, knownProjectNames: [String],
                      now: Date, calendar: Calendar) -> ChatQueryScope {
        var scope = heuristic
        let kinds = resolveKinds(lmKinds)
        if !kinds.isEmpty { scope.kinds = kinds }
        if let project = resolveProject(lmProjectName, knownProjectNames: knownProjectNames) {
            scope.projectName = project
        }
        // "for the project X" names a project — don't also treat "project" as a requested kind.
        if scope.projectName != nil { scope.kinds.remove(.project) }
        if let window = lmPeriod.window(now: now, calendar: calendar) {
            scope.interval = window.range
            scope.intervalLabel = window.label
        }
        scope.wantsTimeTotals = scope.wantsTimeTotals || lmWantsTotals
        scope.wantsOverview = scope.wantsOverview || lmWantsOverview
        return scope
    }
}
