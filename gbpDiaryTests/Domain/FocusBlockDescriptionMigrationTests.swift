import Testing
import Foundation
@testable import gbpDiary

@Suite("FocusBlockDescriptionMigration")
struct FocusBlockDescriptionMigrationTests {
    private func input(_ description: String?, _ project: UUID?) -> FocusBlockDescriptionMigration.Input {
        FocusBlockDescriptionMigration.Input(blockID: UUID(), description: description, projectID: project)
    }

    @Test func blankOrNilDescription_omitted() {
        let p = UUID()
        let plan = FocusBlockDescriptionMigration.plan([input(nil, p), input("   ", p), input("\n", nil)])
        #expect(plan.isEmpty)
    }

    @Test func singleDescribedBlock_oneGroup() {
        let p = UUID()
        let block = input("Design Workshop", p)
        let plan = FocusBlockDescriptionMigration.plan([block])
        #expect(plan.count == 1)
        #expect(plan[0].projectID == p)
        #expect(plan[0].description == "Design Workshop")
        #expect(plan[0].blockIDs == [block.blockID])
    }

    @Test func sameProjectAndDescription_sharesOneTask() {
        let nodes = UUID()
        let b1 = input("Planning", nodes)
        let b2 = input("Planning", nodes)
        let b3 = input("Planning", nodes)
        let plan = FocusBlockDescriptionMigration.plan([b1, b2, b3])
        #expect(plan.count == 1)
        #expect(plan[0].blockIDs == [b1.blockID, b2.blockID, b3.blockID])
    }

    @Test func descriptionTrimmedBeforeGrouping() {
        let p = UUID()
        let b1 = input("Planning", p)
        let b2 = input("  Planning  ", p)
        let plan = FocusBlockDescriptionMigration.plan([b1, b2])
        #expect(plan.count == 1)
        #expect(plan[0].description == "Planning")
        #expect(plan[0].blockIDs == [b1.blockID, b2.blockID])
    }

    @Test func differentProjectOrDescription_splits() {
        let a = UUID(); let b = UUID()
        let plan = FocusBlockDescriptionMigration.plan([
            input("Planning", a),   // group 1
            input("Planning", b),   // group 2 — different project
            input("Comms", a),      // group 3 — different description
        ])
        #expect(plan.count == 3)
    }

    @Test func preservesInputOrder() {
        let p = UUID()
        let plan = FocusBlockDescriptionMigration.plan([input("Zebra", p), input("Apple", p)])
        #expect(plan.map(\.description) == ["Zebra", "Apple"])
    }
}
