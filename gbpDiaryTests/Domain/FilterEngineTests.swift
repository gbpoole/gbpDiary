import Testing
import SwiftUI
@testable import gbpDiary

@Suite("FilterEngine")
struct FilterEngineTests {
    private struct Item: Identifiable {
        let id: Int
        let kind: String
        let owner: String
    }

    private let items = [
        Item(id: 1, kind: "task", owner: "ann"),
        Item(id: 2, kind: "note", owner: "ann"),
        Item(id: 3, kind: "task", owner: "bob"),
        Item(id: 4, kind: "meeting", owner: "cara"),
    ]

    private func kindFilter(_ k: String) -> PickerFilter<Item> {
        PickerFilter(id: "kind.\(k)", label: k, group: "Kind") { $0.kind == k }
    }
    private func ownerFilter(_ o: String) -> PickerFilter<Item> {
        PickerFilter(id: "owner.\(o)", label: o, group: "Owner") { $0.owner == o }
    }

    private var allFilters: [PickerFilter<Item>] {
        [kindFilter("task"), kindFilter("note"), kindFilter("meeting"),
         ownerFilter("ann"), ownerFilter("bob"), ownerFilter("cara")]
    }

    @Test func apply_noActiveFilters_returnsAll() {
        let result = FilterEngine.apply(items, filters: allFilters, activeIds: [])
        #expect(result.map(\.id) == [1, 2, 3, 4])
    }

    @Test func apply_orWithinGroup_matchesAnyInGroup() {
        // kind == task OR kind == note
        let result = FilterEngine.apply(items, filters: allFilters, activeIds: ["kind.task", "kind.note"])
        #expect(Set(result.map(\.id)) == [1, 2, 3])
    }

    @Test func apply_andAcrossGroups_requiresBothGroups() {
        // (kind == task) AND (owner == ann) → only item 1
        let result = FilterEngine.apply(items, filters: allFilters, activeIds: ["kind.task", "owner.ann"])
        #expect(result.map(\.id) == [1])
    }

    @Test func apply_orWithinAndAndAcross_combined() {
        // (kind == task OR note) AND (owner == ann) → items 1 and 2
        let result = FilterEngine.apply(items, filters: allFilters,
                                        activeIds: ["kind.task", "kind.note", "owner.ann"])
        #expect(Set(result.map(\.id)) == [1, 2])
    }

    @Test func apply_groupWithNoActiveFilter_isIgnored() {
        // Only the Owner group is active; Kind group must not narrow the result.
        let result = FilterEngine.apply(items, filters: allFilters, activeIds: ["owner.ann", "owner.bob"])
        #expect(Set(result.map(\.id)) == [1, 2, 3])
    }

    @Test func apply_unknownActiveId_isIgnored() {
        let result = FilterEngine.apply(items, filters: allFilters, activeIds: ["does.not.exist"])
        #expect(result.map(\.id) == [1, 2, 3, 4])
    }
}
