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

    @Test func noteBlock_computeGroups_groupsConsecutiveImagesWithSourceIndices() {
        let textA = NoteBlock.text("A")
        let imageA = NoteBlock.image(UUID())
        let imageB = NoteBlock.image(UUID())
        let textB = NoteBlock.text("B")
        let imageC = NoteBlock.image(UUID())

        let groups = NoteBlock.computeGroups(from: [textA, imageA, imageB, textB, imageC])

        #expect(groups.count == 4)

        guard groups.count == 4 else { return }

        if case .text(let block, let index) = groups[0].content {
            #expect(block.id == textA.id)
            #expect(index == 0)
            #expect(groups[0].firstBlockIndex == 0)
            #expect(groups[0].lastBlockIndex == 0)
        } else {
            Issue.record("Expected first group to be text")
        }

        if case .images(let blocks, let indices) = groups[1].content {
            #expect(blocks.map { $0.id } == [imageA.id, imageB.id])
            #expect(indices == [1, 2])
            #expect(groups[1].id == imageA.id)
            #expect(groups[1].firstBlockIndex == 1)
            #expect(groups[1].lastBlockIndex == 2)
        } else {
            Issue.record("Expected second group to be consecutive images")
        }

        if case .text(let block, let index) = groups[2].content {
            #expect(block.id == textB.id)
            #expect(index == 3)
        } else {
            Issue.record("Expected third group to be text")
        }

        if case .images(let blocks, let indices) = groups[3].content {
            #expect(blocks.map { $0.id } == [imageC.id])
            #expect(indices == [4])
            #expect(groups[3].id == imageC.id)
        } else {
            Issue.record("Expected fourth group to be a single image")
        }
    }
}
