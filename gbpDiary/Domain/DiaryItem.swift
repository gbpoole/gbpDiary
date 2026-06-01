import Foundation

// A unified diary item: either a root diary task (owned by the day via task.dayRecord)
// or a DayEntry (note or meeting). DiaryItems are sorted by sortOrder to interleave
// tasks with notes and meetings in a single coherent list.
enum DiaryItem: Identifiable {
    case task(Task)
    case entry(DayEntry)

    var id: UUID {
        switch self {
        case .task(let t): t.id
        case .entry(let e): e.id
        }
    }

    var sortOrder: Int {
        switch self {
        case .task(let t): t.sortOrder
        case .entry(let e): e.sortOrder
        }
    }

    // Indent level only meaningful for notes and meetings.
    var entryIndentLevel: Int? {
        switch self {
        case .task: nil
        case .entry(let e): e.indentLevel
        }
    }
}
