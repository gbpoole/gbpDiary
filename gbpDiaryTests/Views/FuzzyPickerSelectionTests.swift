import Foundation
import Testing
@testable import gbpDiary

private struct Item: Identifiable, Equatable {
    let id: Int
}

@MainActor
struct FuzzyPickerSelectionTests {

    // MARK: - Multi-select

    @Test func toggling_multiSelect_addsWhenAbsent() {
        let result = FuzzyPickerSelection.toggling(Item(id: 2), in: [Item(id: 1)], maxSelections: .max)
        #expect(result.map(\.id) == [1, 2])
    }

    @Test func toggling_multiSelect_removesWhenPresent() {
        let result = FuzzyPickerSelection.toggling(Item(id: 1), in: [Item(id: 1), Item(id: 2)], maxSelections: .max)
        #expect(result.map(\.id) == [2])
    }

    @Test func toggling_multiSelect_atCap_leavesUnchanged() {
        let result = FuzzyPickerSelection.toggling(Item(id: 3), in: [Item(id: 1), Item(id: 2)], maxSelections: 2)
        #expect(result.map(\.id) == [1, 2])
    }

    // MARK: - Single-select

    @Test func toggling_singleSelect_replacesExistingSelection() {
        let result = FuzzyPickerSelection.toggling(Item(id: 9), in: [Item(id: 1)], maxSelections: 1)
        #expect(result.map(\.id) == [9])
    }

    @Test func toggling_singleSelect_fromEmpty_selectsItem() {
        let result = FuzzyPickerSelection.toggling(Item(id: 9), in: [], maxSelections: 1)
        #expect(result.map(\.id) == [9])
    }

    @Test func toggling_singleSelect_removesWhenSameItemPresent() {
        let result = FuzzyPickerSelection.toggling(Item(id: 9), in: [Item(id: 9)], maxSelections: 1)
        #expect(result.isEmpty)
    }
}
