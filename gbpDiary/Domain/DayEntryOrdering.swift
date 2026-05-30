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
        var inferredLevel = nextLevel > prevLevel ? nextLevel : prevLevel
        // Dropping a non-meeting immediately after a meeting with no deeper entry → land inside it.
        // Not applied for meeting drags so that adjacent meetings can still be reordered as siblings.
        if target > 0, sorted[target - 1].kind == .meeting,
           dragged.kind != .meeting,
           inferredLevel == sorted[target - 1].indentLevel {
            inferredLevel = sorted[target - 1].indentLevel + 1
        }
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

    // Scans sorted entries for consecutive .task DayEntries at indentLevel == meeting.indentLevel + 1
    // immediately following a .meeting entry. Each qualifying task is linked to minutes.newTasks
    // (via task.originMinutes) and its DayEntry is marked for deletion. Sort order within the
    // meeting's task list starts after the current maximum and increments per absorbed task.
    // Orphaned meeting entries (minutes == nil) and orphaned task entries (task == nil) are skipped.
    // Must run AFTER absorbAdjacentNotes so note DayEntries at meeting+1 are consumed first,
    // leaving tasks cleanly adjacent to the meeting.
    @discardableResult
    static func absorbMeetingTasks(in entries: [DayEntry]) -> [DayEntry] {
        let sorted = entries.sorted { $0.sortOrder < $1.sortOrder }
        var toDelete: [DayEntry] = []
        var i = 0
        while i < sorted.count {
            let parent = sorted[i]
            guard parent.kind == .meeting, let minutes = parent.minutes else { i += 1; continue }
            var j = i + 1
            var nextSortOrder = (minutes.newTasks.map(\.meetingTaskSortOrder).max() ?? -1) + 1
            while j < sorted.count {
                let candidate = sorted[j]
                guard candidate.kind == .task,
                      candidate.indentLevel == parent.indentLevel + 1,
                      let task = candidate.task
                else { break }
                task.originMinutes = minutes
                task.meetingTaskSortOrder = nextSortOrder
                nextSortOrder += 1
                toDelete.append(candidate)
                j += 1
            }
            i = j
        }
        return toDelete
    }

    // Scans sorted entries for a .note at indentLevel == parent.indentLevel + 1 immediately
    // following a .task or .meeting entry. When found, appends the note's text into
    // task.notes / minutes.minutesContent (separator "\n\n" when existing content is non-empty)
    // and marks the DayEntry for deletion. The note is only deleted if it was actually
    // absorbed (guards against orphaned task/meeting entries whose relationships are nil).
    // Callers are responsible for deletion and UI side effects.
    // Must run BEFORE mergeAdjacentNotes so absorbed notes are not mistakenly merged first.
    @discardableResult
    static func absorbAdjacentNotes(in entries: [DayEntry])
        -> (redirectMap: [UUID: DayEntry], toDelete: [DayEntry])
    {
        var sorted = entries.sorted { $0.sortOrder < $1.sortOrder }
        var redirectMap: [UUID: DayEntry] = [:]
        var toDelete: [DayEntry] = []
        var i = 0
        while i < sorted.count - 1 {
            let parent = sorted[i], candidate = sorted[i + 1]
            guard (parent.kind == .task || parent.kind == .meeting),
                  candidate.kind == .note,
                  candidate.indentLevel == parent.indentLevel + 1
            else { i += 1; continue }
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { i += 1; continue }
            var absorbed = false
            if parent.kind == .task, let task = parent.task {
                let existing = (task.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                task.notes = existing.isEmpty ? text : existing + "\n\n" + text
                absorbed = true
            } else if parent.kind == .meeting, let minutes = parent.minutes {
                let existing = (minutes.minutesContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                minutes.minutesContent = existing.isEmpty ? text : existing + "\n\n" + text
                absorbed = true
            }
            if absorbed {
                redirectMap[candidate.id] = parent
                toDelete.append(candidate)
                sorted.remove(at: i + 1)
            } else {
                i += 1
            }
        }
        return (redirectMap, toDelete)
    }
}
