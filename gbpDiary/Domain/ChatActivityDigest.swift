import Foundation

// A factual, app-assembled record of what actually happened in a window — the antidote to the model
// inventing a "Saturday meeting". Every item comes from a real SwiftData record with a weekend-folded
// date; the model (if used) only rephrases this block and is told to add nothing. If the model is
// unavailable or misbehaves, `render` IS the answer, so the digest lens can never hallucinate or degrade.
nonisolated struct ChatActivityItem: Equatable, Sendable {
    let date: Date                       // already weekend-folded to a weekday
    let label: String                    // e.g. "Meeting: NODES review (1h)"
    let source: ChatSourceReference?     // for click-through citations

    init(date: Date, label: String, source: ChatSourceReference? = nil) {
        self.date = date
        self.label = label
        self.source = source
    }
}

nonisolated struct ChatActivityDigest: Equatable, Sendable {
    let items: [ChatActivityItem]        // sorted ascending by date

    var isEmpty: Bool { items.isEmpty }

    /// De-duplicated source references for click-through, in item order.
    var sources: [ChatSourceReference] {
        var seen = Set<ChatSourceKey>()
        return items.compactMap(\.source).filter { seen.insert($0.key).inserted }
    }

    /// A compact factual block grouped by weekday — the deterministic answer, and the material the model
    /// is asked to rephrase.
    func render(calendar: Calendar = .current) -> String {
        guard !isEmpty else { return "" }
        var order: [Date] = []
        var byDay: [Date: [String]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.date)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(item.label)
        }
        return order.sorted().map { day in
            let header = Self.dayFormatter.string(from: day)
            let bullets = (byDay[day] ?? []).map { "• \($0)" }.joined(separator: "\n")
            return "\(header):\n\(bullets)"
        }.joined(separator: "\n")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE d MMM"   // always a weekday after folding
        return f
    }()
}

nonisolated enum ChatActivityDigestBuilder {
    /// Keep only the folded items that fall in the window, sorted ascending by date.
    static func build(items: [ChatActivityItem], interval: Range<Date>) -> ChatActivityDigest {
        ChatActivityDigest(items: items.filter { interval.contains($0.date) }.sorted { $0.date < $1.date })
    }

    /// The strict phrasing instruction: the model may only rephrase the supplied block.
    static func phrasingPrompt(block: String, intervalLabel: String?) -> String {
        let period = intervalLabel.map { " for \($0)" } ?? ""
        return """
        Rewrite the following list of the user's activity\(period) into a brief, friendly summary written \
        to "you". Use ONLY these items — do not add, infer, embellish, or omit anything, and never mention \
        a day that is not listed. Keep it concise and grouped by day.

        \(block)
        """
    }
}
