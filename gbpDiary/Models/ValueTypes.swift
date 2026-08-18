import Foundation

enum TaskStatus: String, Codable {
    case todo
    case started
    case completed
    case cancelled
    case followUpPending
}

// Taskwarrior-style priority. `weight` feeds the urgency score (Stage 2); `short` is the H/M/L chip.
enum TaskPriority: String, Codable, CaseIterable {
    case none
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .none:   "None"
        case .low:    "Low"
        case .medium: "Medium"
        case .high:   "High"
        }
    }

    var short: String {
        switch self {
        case .none:   ""
        case .low:    "L"
        case .medium: "M"
        case .high:   "H"
        }
    }

    /// Relative weight (0…1) — Taskwarrior uses H=1.0, M=0.65, L=0.3, none=0.
    var weight: Double {
        switch self {
        case .none:   0.0
        case .low:    0.3
        case .medium: 0.65
        case .high:   1.0
        }
    }

    /// Ordinal for sorting (none=0 … high=3).
    var rank: Int {
        switch self {
        case .none:   0
        case .low:    1
        case .medium: 2
        case .high:   3
        }
    }
}

// Manual per-email importance. Default `.low` is the neutral baseline (no chip, no ranking boost);
// only Medium/High carry signal. Mirrors `TaskPriority`: `weight` feeds the Chat ranking boost, `short`
// is the H/M/L chip (Low shows nothing).
enum EmailImportance: String, Codable, CaseIterable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low:    "Low"
        case .medium: "Medium"
        case .high:   "High"
        }
    }

    var short: String {
        switch self {
        case .low:    ""
        case .medium: "M"
        case .high:   "H"
        }
    }

    /// Relative weight (0…1) — Low is neutral (0), so it applies no Chat ranking boost.
    var weight: Double {
        switch self {
        case .low:    0.0
        case .medium: 0.5
        case .high:   1.0
        }
    }

    /// Ordinal for sorting (low=0 … high=2).
    var rank: Int {
        switch self {
        case .low:    0
        case .medium: 1
        case .high:   2
        }
    }
}

// Quick "created within" windows for the Tasks toolbar date presets (rolling, ending now).
enum DateWindow: String, CaseIterable {
    case today
    case week
    case month

    var label: String {
        switch self {
        case .today: "Today"
        case .week:  "Week"
        case .month: "Month"
        }
    }

    /// `[start, now]` — today = since start-of-today; week = last 7 days; month = last 30 days.
    func range(now: Date = Date(), calendar: Calendar = .current) -> ClosedRange<Date> {
        let startOfToday = calendar.startOfDay(for: now)
        let start: Date
        switch self {
        case .today: start = startOfToday
        case .week:  start = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        case .month: start = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
        }
        return start...now
    }
}

enum DurationUnit: String, Codable {
    case h, d, w

    var hoursPerUnit: Double {
        switch self {
        case .h: 1.0
        case .d: 7.6
        case .w: 38.0
        }
    }

    var label: String { rawValue }
}

struct Duration: Codable, Equatable {
    var value: Double
    var unit: DurationUnit
    var hoursNormalized: Double

    init(value: Double, unit: DurationUnit) {
        self.value = value
        self.unit = unit
        self.hoursNormalized = value * unit.hoursPerUnit
    }

    var displayString: String {
        let v = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        return "\(v)\(unit.label)"
    }

    static func parse(_ text: String) -> Duration? {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }
        let unitChar = s.last!
        let unit: DurationUnit
        switch unitChar {
        case "h": unit = .h
        case "d": unit = .d
        case "w": unit = .w
        default: return nil
        }
        let numStr = String(s.dropLast())
        guard let value = Double(numStr), value > 0 else { return nil }
        return Duration(value: value, unit: unit)
    }
}

enum DayEntryKind: String, Codable {
    case note
    case task
    case meeting
}

/// Whether a cached email was received (INBOX) or sent (Sent mailbox).
enum EmailDirection: String, Codable, CaseIterable {
    case inbox
    case sent
}

enum DaySlot: String, Codable, CaseIterable {
    case allDay
    case morning
    case afternoon
    case evening

    var displayName: String {
        switch self {
        case .allDay:    "All Day"
        case .morning:   "Morning"
        case .afternoon: "Afternoon"
        case .evening:   "Evening"
        }
    }

    // Planned capacity for the slot. Evening is a pure overtime container — no standard capacity.
    var defaultDuration: Duration {
        switch self {
        case .allDay:    Duration(value: 1.0, unit: .d)
        case .morning:   Duration(value: 0.5, unit: .d)
        case .afternoon: Duration(value: 0.5, unit: .d)
        case .evening:   Duration(value: 0.0, unit: .h)
        }
    }

    // Evening time is treated as extra / overtime, not part of the standard working day.
    var isOvertime: Bool { self == .evening }
}

// MARK: - JSON helpers for array attributes
// SwiftData/CoreData cannot materialize Array<String> or Array<Date> at runtime.
// Store them as JSON strings and expose via computed properties instead.

func jsonEncode<T: Encodable>(_ value: T) -> String {
    let data = (try? JSONEncoder().encode(value)) ?? Data()
    return String(data: data, encoding: .utf8) ?? "[]"
}

func jsonDecode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}

// MARK: - Import provenance

struct SourceContext: Codable, Equatable {
    var externalSourceId: String?
    var sourceRecordId: String?
    var sourceSection: String?
    var sourceLineFingerprint: String?
    var importRunId: String?
    var firstSeenAt: Date?
    var lastSeenAt: Date?
}
