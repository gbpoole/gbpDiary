import Foundation

enum TaskStatus: String, Codable {
    case todo
    case started
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

enum DayEntryKind: String, Codable {
    case note
    case task
    case meeting
}

enum DaySlot: String, Codable, CaseIterable {
    case allDay
    case morning
    case afternoon

    var displayName: String {
        switch self {
        case .allDay:    "All Day"
        case .morning:   "Morning"
        case .afternoon: "Afternoon"
        }
    }

    var defaultDuration: Duration {
        switch self {
        case .allDay:    Duration(value: 1.0, unit: .d)
        case .morning:   Duration(value: 0.5, unit: .d)
        case .afternoon: Duration(value: 0.5, unit: .d)
        }
    }
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

// MARK: - Note block types

enum NoteBlockKind: String, Codable {
    case text
    case image
}

enum ImageAlignment: String, Codable, CaseIterable {
    case left
    case center
    case right

    var icon: String {
        switch self {
        case .left:   "text.alignleft"
        case .center: "text.aligncenter"
        case .right:  "text.alignright"
        }
    }
}

struct NoteBlock: Codable, Identifiable {
    var id: UUID = UUID()
    var kind: NoteBlockKind
    var textContent: String = ""
    var attachmentId: UUID?
    var alignment: ImageAlignment = .center

    static func text(_ content: String = "") -> NoteBlock {
        NoteBlock(kind: .text, textContent: content)
    }

    static func image(_ attachmentId: UUID, alignment: ImageAlignment = .center) -> NoteBlock {
        NoteBlock(kind: .image, attachmentId: attachmentId, alignment: alignment)
    }
}

extension NoteBlock {
    // Consecutive .image blocks form an implicit group. This helper computes groups
    // for rendering so image groups can be displayed as a single wrapped row.
    struct BlockGroup: Identifiable {
        enum Content {
            case text(NoteBlock, Int)             // (block, noteBlocksIndex)
            case images([NoteBlock], [Int])       // (blocks, noteBlocksIndices)
        }
        var id: UUID
        var content: Content

        var firstBlockIndex: Int {
            switch content {
            case .text(_, let i): return i
            case .images(_, let idxs): return idxs.first ?? 0
            }
        }
        var lastBlockIndex: Int {
            switch content {
            case .text(_, let i): return i
            case .images(_, let idxs): return idxs.last ?? 0
            }
        }
    }

    static func computeGroups(from blocks: [NoteBlock]) -> [BlockGroup] {
        blocks.enumerated().map { i, block in
            block.kind == .image
                ? BlockGroup(id: block.id, content: .images([block], [i]))
                : BlockGroup(id: block.id, content: .text(block, i))
        }
    }
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
