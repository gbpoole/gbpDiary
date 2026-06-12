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
    // Non-nil means this image belongs to an explicit group; consecutive images with the
    // same groupId render as a single NoteImageGroupRow. nil = standalone image row.
    var groupId: UUID? = nil

    static func text(_ content: String = "") -> NoteBlock {
        NoteBlock(kind: .text, textContent: content)
    }

    static func image(_ attachmentId: UUID, alignment: ImageAlignment = .center) -> NoteBlock {
        NoteBlock(kind: .image, attachmentId: attachmentId, alignment: alignment)
    }
}

// Backward-compatible decoder: handles JSON produced before groupId was added.
extension NoteBlock {
    enum CodingKeys: String, CodingKey {
        case id, kind, textContent, attachmentId, alignment, groupId
    }
    init(from decoder: Decoder) throws {
        let c    = try decoder.container(keyedBy: CodingKeys.self)
        id           = try  c.decode(UUID.self, forKey: .id)
        kind         = try  c.decode(NoteBlockKind.self, forKey: .kind)
        textContent  = (try? c.decodeIfPresent(String.self,          forKey: .textContent))  ?? ""
        attachmentId =  try? c.decodeIfPresent(UUID.self,            forKey: .attachmentId)
        alignment    = (try? c.decodeIfPresent(ImageAlignment.self,  forKey: .alignment))    ?? .center
        groupId      =  try? c.decodeIfPresent(UUID.self,            forKey: .groupId)
    }
}

extension NoteBlock {
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

    // Images with the same non-nil groupId that are consecutive form one visual group.
    // Images with nil groupId or a different groupId are always standalone rows.
    static func computeGroups(from blocks: [NoteBlock]) -> [BlockGroup] {
        var result: [BlockGroup] = []
        var i = 0
        while i < blocks.count {
            if blocks[i].kind == .image, let gid = blocks[i].groupId {
                var imgBlocks: [NoteBlock] = []
                var imgIndices: [Int] = []
                while i < blocks.count && blocks[i].kind == .image && blocks[i].groupId == gid {
                    imgBlocks.append(blocks[i]); imgIndices.append(i); i += 1
                }
                result.append(BlockGroup(id: imgBlocks[0].id, content: .images(imgBlocks, imgIndices)))
            } else {
                let block = blocks[i]
                result.append(BlockGroup(
                    id: block.id,
                    content: block.kind == .image ? .images([block], [i]) : .text(block, i)
                ))
                i += 1
            }
        }
        return result
    }

    // Clear groupId from images whose group was reduced to a single member so they
    // revert to standalone appearance. Call after any groupId mutation.
    static func cleanupGroupIds(in blocks: inout [NoteBlock]) {
        var counts: [UUID: Int] = [:]
        for b in blocks where b.kind == .image { if let g = b.groupId { counts[g, default: 0] += 1 } }
        for i in blocks.indices where blocks[i].kind == .image {
            if let g = blocks[i].groupId, counts[g] == 1 { blocks[i].groupId = nil }
        }
    }

    // MARK: - Shift-arrow mutations
    // Each returns nil when the action doesn't apply (no-op), or the full mutated array.

    static func shiftLeft(blocks: [NoteBlock], selId: UUID) -> [NoteBlock]? {
        guard let idx = blocks.firstIndex(where: { $0.id == selId }),
              idx > 0,
              blocks[idx].kind == .image,
              blocks[idx - 1].kind == .image,
              let gid = blocks[idx].groupId,
              blocks[idx - 1].groupId == gid else { return nil }
        var b = blocks
        b.swapAt(idx, idx - 1)
        cleanupGroupIds(in: &b); return b
    }

    static func shiftRight(blocks: [NoteBlock], selId: UUID) -> [NoteBlock]? {
        guard let idx = blocks.firstIndex(where: { $0.id == selId }),
              idx < blocks.count - 1,
              blocks[idx].kind == .image,
              blocks[idx + 1].kind == .image,
              let gid = blocks[idx].groupId,
              blocks[idx + 1].groupId == gid else { return nil }
        var b = blocks
        b.swapAt(idx, idx + 1)
        cleanupGroupIds(in: &b); return b
    }

    static func shiftUp(blocks: [NoteBlock], selId: UUID) -> [NoteBlock]? {
        guard let idx = blocks.firstIndex(where: { $0.id == selId }) else { return nil }
        var b = blocks
        guard b[idx].kind == .image else {
            guard idx > 0 else { return nil }
            b.swapAt(idx, idx - 1); cleanupGroupIds(in: &b); return b
        }
        let curGid = b[idx].groupId
        let inGroup = curGid != nil && b.contains(where: { $0.id != selId && $0.groupId == curGid })
        if inGroup, let gid = curGid {
            // Extract before the group; if already at index 0 it stays there but becomes standalone
            var groupStart = idx
            while groupStart > 0 && b[groupStart - 1].kind == .image && b[groupStart - 1].groupId == gid {
                groupStart -= 1
            }
            var extracted = b.remove(at: idx); extracted.groupId = nil
            b.insert(extracted, at: groupStart)
        } else if idx > 0 && b[idx - 1].kind == .image {
            let prevGid = b[idx - 1].groupId
            let gid = prevGid ?? UUID()
            if prevGid == nil { b[idx - 1].groupId = gid }
            b[idx].groupId = gid
        } else if idx > 0 {
            b[idx].groupId = nil; b.swapAt(idx, idx - 1)
        } else {
            return nil
        }
        cleanupGroupIds(in: &b); return b
    }

    static func shiftDown(blocks: [NoteBlock], selId: UUID) -> [NoteBlock]? {
        guard let idx = blocks.firstIndex(where: { $0.id == selId }) else { return nil }
        var b = blocks
        guard b[idx].kind == .image else {
            guard idx < b.count - 1 else { return nil }
            b.swapAt(idx, idx + 1); cleanupGroupIds(in: &b); return b
        }
        let curGid = b[idx].groupId
        let inGroup = curGid != nil && b.contains(where: { $0.id != selId && $0.groupId == curGid })
        if inGroup, let gid = curGid {
            // Extract after the group; if already at last index it stays there but becomes standalone
            var groupEnd = idx
            while groupEnd < b.count - 1 && b[groupEnd + 1].kind == .image && b[groupEnd + 1].groupId == gid {
                groupEnd += 1
            }
            var extracted = b.remove(at: idx); extracted.groupId = nil
            b.insert(extracted, at: groupEnd)
        } else if idx < b.count - 1 && b[idx + 1].kind == .image {
            let nextGid = b[idx + 1].groupId
            let gid = nextGid ?? UUID()
            if nextGid == nil { b[idx + 1].groupId = gid }
            b[idx].groupId = gid
        } else if idx < b.count - 1 {
            b[idx].groupId = nil; b.swapAt(idx, idx + 1)
        } else {
            return nil
        }
        cleanupGroupIds(in: &b); return b
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
