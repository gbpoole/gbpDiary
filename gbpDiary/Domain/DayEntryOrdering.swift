import Foundation

enum DayEntryOrdering {
    static func indent(entry: DayEntry, in entries: [DayEntry]) {
        let sorted = entries.sorted { $0.sortOrder < $1.sortOrder }
        guard let idx = sorted.firstIndex(where: { $0.id == entry.id }) else { return }
        let base = entry.indentLevel
        entry.indentLevel = min(base + 1, 6)
        for child in sorted.dropFirst(idx + 1) {
            guard child.indentLevel > base else { break }
            child.indentLevel = min(child.indentLevel + 1, 6)
        }
    }

    static func outdent(entry: DayEntry, in entries: [DayEntry]) {
        guard entry.indentLevel > 0 else { return }
        let sorted = entries.sorted { $0.sortOrder < $1.sortOrder }
        guard let idx = sorted.firstIndex(where: { $0.id == entry.id }) else { return }
        let base = entry.indentLevel
        entry.indentLevel = max(base - 1, 0)
        for child in sorted.dropFirst(idx + 1) {
            guard child.indentLevel > base else { break }
            child.indentLevel = max(child.indentLevel - 1, 0)
        }
    }

    static func moveEntry(_ dragged: DayEntry, toDropIndex dropIndex: Int, in entries: [DayEntry]) {
        var sorted = entries.sorted { $0.sortOrder < $1.sortOrder }
        guard let fromIndex = sorted.firstIndex(where: { $0.id == dragged.id }) else { return }
        sorted.remove(at: fromIndex)
        let target = min(dropIndex > fromIndex ? dropIndex - 1 : dropIndex, sorted.count)
        let prevLevel = target > 0 ? sorted[target - 1].indentLevel : 0
        let nextLevel = target < sorted.count ? sorted[target].indentLevel : 0
        dragged.indentLevel = nextLevel > prevLevel ? nextLevel : prevLevel
        sorted.insert(dragged, at: target)
        for (i, entry) in sorted.enumerated() {
            entry.sortOrder = i
        }
    }
}
