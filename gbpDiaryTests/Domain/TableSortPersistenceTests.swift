import Foundation
import Testing
@testable import gbpDiary

private struct Row {
    var name: String
    var count: Int
}

@MainActor
struct TableSortPersistenceTests {
    private let columns: [SortColumn<Row>] = [
        SortColumn("name", \.name),
        SortColumn("count", \.count),
    ]

    @Test func descriptor_mapsColumnAndAscending() {
        let asc = TableSortPersistence.descriptor(for: [KeyPathComparator(\Row.name, order: .forward)], columns: columns)
        #expect(asc?.id == "name")
        #expect(asc?.ascending == true)

        let desc = TableSortPersistence.descriptor(for: [KeyPathComparator(\Row.count, order: .reverse)], columns: columns)
        #expect(desc?.id == "count")
        #expect(desc?.ascending == false)
    }

    @Test func descriptor_unknownColumn_returnsNil() {
        // A comparator whose key path is not among `columns`.
        let unknown = TableSortPersistence.descriptor(for: [KeyPathComparator(\Row.name, order: .forward)],
                                                      columns: [SortColumn("count", \.count)])
        #expect(unknown == nil)
    }

    @Test func order_roundTripsDescriptor() {
        let order = TableSortPersistence.order(id: "count", ascending: false, columns: columns, fallbackID: "name")
        let d = TableSortPersistence.descriptor(for: order, columns: columns)
        #expect(d?.id == "count")
        #expect(d?.ascending == false)
    }

    @Test func order_unknownId_fallsBack() {
        let order = TableSortPersistence.order(id: "missing", ascending: true, columns: columns, fallbackID: "name")
        let d = TableSortPersistence.descriptor(for: order, columns: columns)
        #expect(d?.id == "name")
        #expect(d?.ascending == true)
    }
}
