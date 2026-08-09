import Foundation

// Pure recurrence rule: a count + unit (e.g. "1w", "2mo"). Completing a recurring task spawns the next
// instance with its due date advanced by the rule.
struct RecurrenceRule: Equatable {
    enum Unit: String, CaseIterable {
        case day = "d", week = "w", month = "mo", year = "y"
        var component: Calendar.Component {
            switch self {
            case .day:   .day
            case .week:  .weekOfYear
            case .month: .month
            case .year:  .year
            }
        }
        var label: String {
            switch self {
            case .day: "day"; case .week: "week"; case .month: "month"; case .year: "year"
            }
        }
    }

    var count: Int
    var unit: Unit

    /// Parse "1w" / "2mo" / "3d" / "y" (bare unit → count 1). Returns nil for invalid input.
    static func parse(_ raw: String) -> RecurrenceRule? {
        let t = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }
        let digits = t.prefix { $0.isNumber }
        let rest = String(t.dropFirst(digits.count))
        let count = digits.isEmpty ? 1 : (Int(digits) ?? 0)
        guard count > 0, let unit = Unit(rawValue: rest) else { return nil }
        return RecurrenceRule(count: count, unit: unit)
    }

    /// Canonical string form ("1w").
    var normalized: String { "\(count)\(unit.rawValue)" }

    /// The next occurrence after `date`.
    func next(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: unit.component, value: count, to: date) ?? date
    }
}
