import Foundation

// A single sortable column of a macOS `Table`, identified by a stable string id so the current sort
// can be persisted. `make(ascending:)` builds the `KeyPathComparator` for a direction; `matches`
// recognises a comparator as belonging to this column (by key path), so a live `sortOrder` can be
// mapped back to `(id, ascending)`.
struct SortColumn<Model> {
    let id: String
    let make: (_ ascending: Bool) -> KeyPathComparator<Model>
    let matches: (KeyPathComparator<Model>) -> Bool

    init(id: String,
         make: @escaping (Bool) -> KeyPathComparator<Model>,
         matches: @escaping (KeyPathComparator<Model>) -> Bool) {
        self.id = id
        self.make = make
        self.matches = matches
    }

    /// Convenience for the common single-key-path column.
    init<Value: Comparable>(_ id: String, _ keyPath: KeyPath<Model, Value>) {
        self.id = id
        self.make = { KeyPathComparator(keyPath, order: $0 ? .forward : .reverse) }
        self.matches = { $0.keyPath == keyPath }
    }
}

// Pure mapping between a `Table`'s `[KeyPathComparator<Model>]` sort order and a persistable
// `(columnID, ascending)` descriptor. See `SortColumn`.
enum TableSortPersistence {
    /// The persistable descriptor for the current sort order, or nil when it matches no known column.
    static func descriptor<Model>(for order: [KeyPathComparator<Model>],
                                  columns: [SortColumn<Model>]) -> (id: String, ascending: Bool)? {
        guard let first = order.first,
              let match = columns.first(where: { $0.matches(first) }) else { return nil }
        return (match.id, first.order == .forward)
    }

    /// The sort order for a persisted descriptor, falling back to `fallbackID` (then the first column)
    /// when `id` is unknown.
    static func order<Model>(id: String, ascending: Bool,
                             columns: [SortColumn<Model>],
                             fallbackID: String) -> [KeyPathComparator<Model>] {
        let column = columns.first { $0.id == id }
            ?? columns.first { $0.id == fallbackID }
            ?? columns.first
        guard let column else { return [] }
        return [column.make(ascending)]
    }
}
