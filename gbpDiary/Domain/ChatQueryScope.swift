import Foundation

// A structured reading of a Chat question, used to scope retrieval (kind + project + recency) and to
// decide the answer shape + whether to compute time totals. Pure/heuristic: when nothing is detected the
// scope is empty and retrieval is unchanged.
nonisolated struct ChatQueryScope: Equatable, Sendable {
    var kinds: Set<ChatSourceKind> = []
    var projectName: String? = nil        // matched known project name (original case)
    var interval: Range<Date>? = nil      // date window for recency + time totals
    var intervalLabel: String? = nil      // human label for the totals header, e.g. "this week"
    var wantsOverview: Bool = false       // prose vs the default themed bullets
    var wantsTimeTotals: Bool = false     // report deterministic hours totals

    var isEmpty: Bool {
        kinds.isEmpty && projectName == nil && interval == nil && !wantsOverview && !wantsTimeTotals
    }

    /// Fill fields the current question left unspecified from a prior question's scope. Used for
    /// back-referencing follow-ups ("give me the time totals for that as well") so the project, interval,
    /// and kind carry over from the question they refer back to.
    func inheriting(from prior: ChatQueryScope) -> ChatQueryScope {
        var merged = self
        if merged.projectName == nil { merged.projectName = prior.projectName }
        if merged.interval == nil { merged.interval = prior.interval; merged.intervalLabel = prior.intervalLabel }
        if merged.kinds.isEmpty { merged.kinds = prior.kinds }
        return merged
    }
}

nonisolated enum ChatQueryScopeParser {
    static func parse(question: String, knownProjectNames: [String],
                      now: Date = Date(), calendar: Calendar = .current) -> ChatQueryScope {
        let normalized = normalize(question)
        var scope = ChatQueryScope()

        scope.kinds = kinds(in: normalized)
        scope.projectName = matchedProject(normalized: normalized, knownProjectNames: knownProjectNames)
        // "for the project X" names a project — don't also treat "project" as a requested kind.
        if scope.projectName != nil { scope.kinds.remove(.project) }

        if let (range, label) = interval(in: normalized, now: now, calendar: calendar) {
            scope.interval = range
            scope.intervalLabel = label
        }
        scope.wantsOverview = containsAny(normalized, ["overview", "paragraph", "prose", "narrative"])
        scope.wantsTimeTotals = containsAny(normalized,
            ["time spent", "time on", "how long", "how much time", "total time", "time total",
             "time totals", "totals", "hours", "time did"])
        return scope
    }

    /// True when the question refers back to a previous answer rather than standing alone
    /// ("...for that", "as well", "the same", "again"), so its scope should inherit prior context.
    static func isBackReference(_ question: String) -> Bool {
        let normalized = normalize(question)
        // "this"/"these" are excluded — too ambiguous with "this week"/"this month".
        let words = Set(normalized.split(separator: " ").map(String.init))
        if !words.isDisjoint(with: ["that", "those", "them", "it", "same", "again"]) { return true }
        return containsAny(normalized, ["as well", "as well as"])
    }

    // MARK: Kinds

    private static let kindKeywords: [(String, ChatSourceKind)] = [
        ("emails", .email), ("email", .email),
        ("tasks", .task), ("task", .task), ("todos", .task), ("todo", .task),
        ("meetings", .meeting), ("meeting", .meeting), ("minutes", .meeting),
        ("notes", .note), ("note", .note),
        ("people", .person), ("person", .person),
        ("institutions", .institution), ("institution", .institution),
        ("documents", .document), ("document", .document), ("docs", .document),
        ("projects", .project), ("project", .project),
        ("diary", .day), ("days", .day), ("day", .day)
    ]

    private static func kinds(in normalized: String) -> Set<ChatSourceKind> {
        let words = Set(normalized.split(separator: " ").map(String.init))
        var result: Set<ChatSourceKind> = []
        for (word, kind) in kindKeywords where words.contains(word) { result.insert(kind) }
        return result
    }

    // MARK: Project

    private static func matchedProject(normalized: String, knownProjectNames: [String]) -> String? {
        // Longest known project name whose normalised form appears in the normalised question.
        knownProjectNames
            .map { (name: $0, norm: normalize($0)) }
            .filter { !$0.norm.isEmpty && normalized.contains($0.norm) }
            .max { $0.norm.count < $1.norm.count }
            .map(\.name)
    }

    // MARK: Interval

    private static func interval(in normalized: String, now: Date, calendar: Calendar) -> (Range<Date>, String)? {
        let startOfToday = calendar.startOfDay(for: now)
        func day(_ d: Date) -> Date { calendar.startOfDay(for: d) }
        func plusDays(_ n: Int, _ d: Date) -> Date { calendar.date(byAdding: .day, value: n, to: d) ?? d }

        if normalized.contains("today") {
            return (startOfToday..<plusDays(1, startOfToday), "today")
        }
        if normalized.contains("yesterday") {
            return (plusDays(-1, startOfToday)..<startOfToday, "yesterday")
        }
        if normalized.contains("this week"), let w = calendar.dateInterval(of: .weekOfYear, for: now) {
            return (w.start..<w.end, "this week")
        }
        if normalized.contains("last week"), let w = calendar.dateInterval(of: .weekOfYear, for: now),
           let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: w.start) {
            return (prev..<w.start, "last week")
        }
        if normalized.contains("this month"), let m = calendar.dateInterval(of: .month, for: now) {
            return (m.start..<m.end, "this month")
        }
        if normalized.contains("last month"), let m = calendar.dateInterval(of: .month, for: now),
           let prev = calendar.date(byAdding: .month, value: -1, to: m.start) {
            return (prev..<m.start, "last month")
        }
        if normalized.contains("this year"), let y = calendar.dateInterval(of: .year, for: now) {
            return (y.start..<y.end, "this year")
        }
        if let (n, unit, comp) = pastN(in: normalized) {
            let start = calendar.date(byAdding: comp, value: -n, to: startOfToday) ?? startOfToday
            return (start..<plusDays(1, startOfToday), "the past \(n) \(unit)\(n == 1 ? "" : "s")")
        }
        if containsAny(normalized, ["recent", "recently", "lately"]) {
            return (plusDays(-13, startOfToday)..<plusDays(1, startOfToday), "recently")
        }
        return nil
    }

    // Matches "(past|last) N day(s)/week(s)/month(s)".
    private static func pastN(in normalized: String) -> (Int, String, Calendar.Component)? {
        let pattern = #"(?:past|last)\s+(\d+)\s+(day|week|month)s?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let nRange = Range(match.range(at: 1), in: normalized),
              let uRange = Range(match.range(at: 2), in: normalized),
              let n = Int(normalized[nRange]) else { return nil }
        switch String(normalized[uRange]) {
        case "day":   return (n, "day", .day)
        case "week":  return (n, "week", .weekOfYear)
        case "month": return (n, "month", .month)
        default:      return nil
        }
    }

    // MARK: Helpers

    private static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let collapsed = lowered.unicodeScalars.map { scalar -> Character in
            (CharacterSet.alphanumerics.contains(scalar) || scalar == " ") ? Character(scalar) : " "
        }
        return String(collapsed).split(separator: " ").joined(separator: " ")
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
