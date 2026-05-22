import Foundation

enum TaskStatus: String, Codable {
    case open
    case completed
    case cancelled
    case followUpPending
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

struct SourceContext: Codable, Equatable {
    var externalSourceId: String?
    var sourceRecordId: String?
    var sourceSection: String?
    var sourceLineFingerprint: String?
    var importRunId: String?
    var firstSeenAt: Date?
    var lastSeenAt: Date?
}
