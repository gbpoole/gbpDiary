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
}
