import Foundation

// Encodes which tasks a board drag is carrying.
//
// SwiftUI's `.draggable` on a plain view carries exactly ONE item, so a multi-card drag can't work the
// way `Table`'s multi-row drag does. Instead the whole selection travels as a single payload string
// and is split on arrival. Drop handlers receive `[String]` (one per dragged item), so decoding takes
// an array and flattens it.
enum BoardDragPayload {
    private static let separator = ","

    /// One payload carrying every id in the drag.
    static func encode(_ ids: [UUID]) -> String {
        ids.map(\.uuidString).joined(separator: separator)
    }

    /// The ids in one or more payloads, in order, ignoring anything unparseable and dropping repeats.
    static func decode(_ payloads: [String]) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for payload in payloads {
            for piece in payload.split(separator: Character(separator)) {
                guard let id = UUID(uuidString: piece.trimmingCharacters(in: .whitespaces)) else { continue }
                if seen.insert(id).inserted { result.append(id) }
            }
        }
        return result
    }
}
