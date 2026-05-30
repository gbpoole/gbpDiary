import Foundation

enum DayEntryOrdering {
    @discardableResult
    static func indent(entry: DayEntry, in entries: [DayEntry]) -> Bool {
        let sorted = entries.sorted { $0.sortOrder < $1.sortOrder }
        guard let idx = sorted.firstIndex(where: { $0.id == entry.id }) else { return false }
        let base = entry.indentLevel
        let newLevel = min(base + 1, 6)
        if entry.kind == .meeting {
            for i in (0..<idx).reversed() {
                if sorted[i].indentLevel < newLevel {
                    if sorted[i].kind == .meeting { return false }
                    break
                }
            }
        }
        entry.indentLevel = newLevel
        for child in sorted.dropFirst(idx + 1) {
            guard child.indentLevel > base else { break }
            child.indentLevel = min(child.indentLevel + 1, 6)
        }
        return true
    }

    @discardableResult
    static func outdent(entry: DayEntry, in entries: [DayEntry]) -> Bool {
        guard entry.indentLevel > 0 else { return false }
        let sorted = entries.sorted { $0.sortOrder < $1.sortOrder }
        guard let idx = sorted.firstIndex(where: { $0.id == entry.id }) else { return false }
        let base = entry.indentLevel
        let newLevel = max(base - 1, 0)
        if entry.kind == .meeting && newLevel > 0 {
            for i in (0..<idx).reversed() {
                if sorted[i].indentLevel < newLevel {
                    if sorted[i].kind == .meeting { return false }
                    break
                }
            }
        }
        entry.indentLevel = newLevel
        for child in sorted.dropFirst(idx + 1) {
            guard child.indentLevel > base else { break }
            child.indentLevel = max(child.indentLevel - 1, 0)
        }
        return true
    }

    @discardableResult
    static func moveEntry(_ dragged: DayEntry, toDropIndex dropIndex: Int, in entries: [DayEntry]) -> Bool {
        var sorted = entries.sorted { $0.sortOrder < $1.sortOrder }
        guard let fromIndex = sorted.firstIndex(where: { $0.id == dragged.id }) else { return false }
        sorted.remove(at: fromIndex)
        let target = min(dropIndex > fromIndex ? dropIndex - 1 : dropIndex, sorted.count)
        let prevLevel = target > 0 ? sorted[target - 1].indentLevel : 0
        let nextLevel = target < sorted.count ? sorted[target].indentLevel : 0
        let inferredLevel = nextLevel > prevLevel ? nextLevel : prevLevel
        if dragged.kind == .meeting && inferredLevel > 0 {
            for i in (0..<target).reversed() {
                if sorted[i].indentLevel < inferredLevel {
                    if sorted[i].kind == .meeting { return false }
                    break
                }
            }
        }
        dragged.indentLevel = inferredLevel
        sorted.insert(dragged, at: target)
        for (i, entry) in sorted.enumerated() {
            entry.sortOrder = i
        }
        return true
    }

    // Scans sorted entries for consecutive .note pairs where both are non-empty
    // and merges each pair: absorbs B into A with a "\n\n" separator, then
    // continues scanning (chains). Returns a redirect map (deleted id → absorber)
    // and the list of entries that should be deleted from the model context.
    // Callers are responsible for the actual deletion and any UI side effects.
    @discardableResult
    static func mergeAdjacentNotes(in entries: [DayEntry]) -> (redirectMap: [UUID: DayEntry], toDelete: [DayEntry]) {
        var sorted = entries.sorted { $0.sortOrder < $1.sortOrder }
        var redirectMap: [UUID: DayEntry] = [:]
        var toDelete: [DayEntry] = []
        var i = 0
        while i < sorted.count - 1 {
            let a = sorted[i], b = sorted[i + 1]
            if a.kind == .note && b.kind == .note && !a.text.isEmpty && !b.text.isEmpty {
                a.text = a.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    + "\n\n"
                    + b.text.trimmingCharacters(in: .whitespacesAndNewlines)
                redirectMap[b.id] = a
                toDelete.append(b)
                sorted.remove(at: i + 1)
            } else {
                i += 1
            }
        }
        return (redirectMap, toDelete)
    }
}
