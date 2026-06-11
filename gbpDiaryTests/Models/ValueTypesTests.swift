import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct ValueTypesTests {

    // MARK: - DaySlot.displayName

    @Test func daySlot_displayNames() {
        #expect(DaySlot.allDay.displayName == "All Day")
        #expect(DaySlot.morning.displayName == "Morning")
        #expect(DaySlot.afternoon.displayName == "Afternoon")
    }

    // MARK: - DaySlot.defaultDuration

    @Test func daySlot_defaultDuration_allDay_isOneDay() {
        let dur = DaySlot.allDay.defaultDuration
        #expect(dur.value == 1.0)
        #expect(dur.unit == .d)
        #expect(dur.hoursNormalized == 7.6)
    }

    @Test func daySlot_defaultDuration_morning_isHalfDay() {
        let dur = DaySlot.morning.defaultDuration
        #expect(dur.value == 0.5)
        #expect(dur.unit == .d)
        #expect(dur.hoursNormalized == 3.8)
    }

    @Test func daySlot_defaultDuration_afternoon_isHalfDay() {
        let dur = DaySlot.afternoon.defaultDuration
        #expect(dur.value == 0.5)
        #expect(dur.unit == .d)
        #expect(dur.hoursNormalized == 3.8)
    }

    // MARK: - NoteBlock.computeGroups

    @Test func noteBlock_computeGroups_eachImageIsOwnGroup() {
        let textA = NoteBlock.text("A")
        let imageA = NoteBlock.image(UUID())
        let imageB = NoteBlock.image(UUID())
        let textB = NoteBlock.text("B")
        let imageC = NoteBlock.image(UUID())

        let groups = NoteBlock.computeGroups(from: [textA, imageA, imageB, textB, imageC])

        // Each block is its own group — consecutive images are no longer merged.
        #expect(groups.count == 5)

        guard groups.count == 5 else { return }

        if case .text(let block, let index) = groups[0].content {
            #expect(block.id == textA.id); #expect(index == 0)
        } else { Issue.record("groups[0] expected text") }

        if case .images(let blocks, let indices) = groups[1].content {
            #expect(blocks.map { $0.id } == [imageA.id])
            #expect(indices == [1])
            #expect(groups[1].firstBlockIndex == 1); #expect(groups[1].lastBlockIndex == 1)
        } else { Issue.record("groups[1] expected single-image group") }

        if case .images(let blocks, let indices) = groups[2].content {
            #expect(blocks.map { $0.id } == [imageB.id])
            #expect(indices == [2])
            #expect(groups[2].firstBlockIndex == 2); #expect(groups[2].lastBlockIndex == 2)
        } else { Issue.record("groups[2] expected single-image group") }

        if case .text(let block, let index) = groups[3].content {
            #expect(block.id == textB.id); #expect(index == 3)
        } else { Issue.record("groups[3] expected text") }

        if case .images(let blocks, let indices) = groups[4].content {
            #expect(blocks.map { $0.id } == [imageC.id])
            #expect(indices == [4])
        } else { Issue.record("groups[4] expected single-image group") }
    }
}
