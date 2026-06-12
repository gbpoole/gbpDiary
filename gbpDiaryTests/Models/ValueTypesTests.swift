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

    @Test func noteBlock_computeGroups_groupsImagesByExplicitGroupId() {
        let gid = UUID()
        var imgA = NoteBlock.image(UUID()); imgA.groupId = gid
        var imgB = NoteBlock.image(UUID()); imgB.groupId = gid
        let imgC = NoteBlock.image(UUID())            // standalone (nil groupId)
        let text = NoteBlock.text("T")

        let groups = NoteBlock.computeGroups(from: [imgA, imgB, text, imgC])

        #expect(groups.count == 3)
        guard groups.count == 3 else { return }

        if case .images(let blocks, let indices) = groups[0].content {
            #expect(blocks.count == 2)
            #expect(blocks[0].id == imgA.id); #expect(blocks[1].id == imgB.id)
            #expect(indices == [0, 1])
        } else { Issue.record("groups[0] expected two-image group") }

        if case .text = groups[1].content { } else { Issue.record("groups[1] expected text") }

        if case .images(let blocks, _) = groups[2].content {
            #expect(blocks.count == 1)
            #expect(blocks[0].id == imgC.id)
        } else { Issue.record("groups[2] expected standalone image") }
    }

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

    // MARK: - NoteBlock.shiftLeft

    @Test func shiftLeft_sameGroup_reordersWithinGroup() {
        let gid = UUID()
        var a = NoteBlock.image(UUID()); a.groupId = gid
        var b = NoteBlock.image(UUID()); b.groupId = gid
        let result = NoteBlock.shiftLeft(blocks: [a, b], selId: b.id)
        #expect(result != nil)
        guard let r = result else { return }
        #expect(r[0].id == b.id); #expect(r[1].id == a.id)
        #expect(r[0].groupId == gid); #expect(r[1].groupId == gid)
    }

    @Test func shiftLeft_differentGroups_returnsNil() {
        let gid1 = UUID(); let gid2 = UUID()
        var a = NoteBlock.image(UUID()); a.groupId = gid1
        var b = NoteBlock.image(UUID()); b.groupId = gid2
        #expect(NoteBlock.shiftLeft(blocks: [a, b], selId: b.id) == nil)
    }

    @Test func shiftLeft_standaloneWithStandalone_returnsNil() {
        let a = NoteBlock.image(UUID())
        let b = NoteBlock.image(UUID())
        #expect(NoteBlock.shiftLeft(blocks: [a, b], selId: b.id) == nil)
    }

    @Test func shiftLeft_noImageLeft_returnsNil() {
        let text = NoteBlock.text("T")
        let img  = NoteBlock.image(UUID())
        #expect(NoteBlock.shiftLeft(blocks: [text, img], selId: img.id) == nil)
    }

    @Test func shiftLeft_atStart_returnsNil() {
        let img = NoteBlock.image(UUID())
        #expect(NoteBlock.shiftLeft(blocks: [img], selId: img.id) == nil)
    }

    // MARK: - NoteBlock.shiftRight

    @Test func shiftRight_sameGroup_reordersWithinGroup() {
        let gid = UUID()
        var a = NoteBlock.image(UUID()); a.groupId = gid
        var b = NoteBlock.image(UUID()); b.groupId = gid
        let result = NoteBlock.shiftRight(blocks: [a, b], selId: a.id)
        #expect(result != nil)
        guard let r = result else { return }
        #expect(r[0].id == b.id); #expect(r[1].id == a.id)
        #expect(r[0].groupId == gid); #expect(r[1].groupId == gid)
    }

    @Test func shiftRight_differentGroups_returnsNil() {
        let gid1 = UUID(); let gid2 = UUID()
        var a = NoteBlock.image(UUID()); a.groupId = gid1
        var b = NoteBlock.image(UUID()); b.groupId = gid2
        #expect(NoteBlock.shiftRight(blocks: [a, b], selId: a.id) == nil)
    }

    @Test func shiftRight_standaloneWithStandalone_returnsNil() {
        let a = NoteBlock.image(UUID())
        let b = NoteBlock.image(UUID())
        #expect(NoteBlock.shiftRight(blocks: [a, b], selId: a.id) == nil)
    }

    @Test func shiftRight_noImageRight_returnsNil() {
        let img  = NoteBlock.image(UUID())
        let text = NoteBlock.text("T")
        #expect(NoteBlock.shiftRight(blocks: [img, text], selId: img.id) == nil)
    }

    @Test func shiftRight_atEnd_returnsNil() {
        let img = NoteBlock.image(UUID())
        #expect(NoteBlock.shiftRight(blocks: [img], selId: img.id) == nil)
    }

    // MARK: - NoteBlock.shiftUp

    @Test func shiftUp_inGroup_extractsBeforeGroup() {
        let gid = UUID()
        var a = NoteBlock.image(UUID()); a.groupId = gid
        var b = NoteBlock.image(UUID()); b.groupId = gid
        var c = NoteBlock.image(UUID()); c.groupId = gid
        let result = NoteBlock.shiftUp(blocks: [a, b, c], selId: b.id)
        #expect(result != nil)
        guard let r = result else { return }
        // b should be extracted before the group (index 0), standalone
        #expect(r[0].id == b.id); #expect(r[0].groupId == nil)
        #expect(r[1].id == a.id); #expect(r[2].id == c.id)
        #expect(r[1].groupId == gid); #expect(r[2].groupId == gid)
    }

    @Test func shiftUp_inGroup_firstElement_extractsBeforeGroup() {
        let gid = UUID()
        var a = NoteBlock.image(UUID()); a.groupId = gid
        var b = NoteBlock.image(UUID()); b.groupId = gid
        let result = NoteBlock.shiftUp(blocks: [a, b], selId: a.id)
        #expect(result != nil)
        guard let r = result else { return }
        // a extracted before group (index 0, still first), standalone; b becomes sole member → cleanup clears gid
        #expect(r[0].id == a.id); #expect(r[0].groupId == nil)
        #expect(r[1].id == b.id); #expect(r[1].groupId == nil)
    }

    @Test func shiftUp_standaloneWithGroupedAbove_mergesAtEnd() {
        let gid = UUID()
        var a = NoteBlock.image(UUID()); a.groupId = gid
        let b = NoteBlock.image(UUID())  // standalone
        let result = NoteBlock.shiftUp(blocks: [a, b], selId: b.id)
        #expect(result != nil)
        guard let r = result else { return }
        #expect(r[0].groupId == gid); #expect(r[1].groupId == gid)
    }

    @Test func shiftUp_standaloneWithStandaloneAbove_createsGroup() {
        let a = NoteBlock.image(UUID())
        let b = NoteBlock.image(UUID())
        let result = NoteBlock.shiftUp(blocks: [a, b], selId: b.id)
        #expect(result != nil)
        guard let r = result else { return }
        #expect(r[0].groupId != nil); #expect(r[0].groupId == r[1].groupId)
    }

    @Test func shiftUp_standaloneWithTextAbove_swaps() {
        let text = NoteBlock.text("T")
        let img  = NoteBlock.image(UUID())
        let result = NoteBlock.shiftUp(blocks: [text, img], selId: img.id)
        #expect(result != nil)
        guard let r = result else { return }
        #expect(r[0].id == img.id); #expect(r[1].id == text.id)
    }

    @Test func shiftUp_atStart_returnsNil() {
        let img = NoteBlock.image(UUID())
        #expect(NoteBlock.shiftUp(blocks: [img], selId: img.id) == nil)
    }

    // MARK: - NoteBlock.shiftDown

    @Test func shiftDown_inGroup_extractsAfterGroup() {
        let gid = UUID()
        var a = NoteBlock.image(UUID()); a.groupId = gid
        var b = NoteBlock.image(UUID()); b.groupId = gid
        var c = NoteBlock.image(UUID()); c.groupId = gid
        let result = NoteBlock.shiftDown(blocks: [a, b, c], selId: b.id)
        #expect(result != nil)
        guard let r = result else { return }
        // b extracted after group (index 2), standalone
        #expect(r[0].id == a.id); #expect(r[1].id == c.id); #expect(r[2].id == b.id)
        #expect(r[0].groupId == gid); #expect(r[1].groupId == gid); #expect(r[2].groupId == nil)
    }

    @Test func shiftDown_inGroup_lastElement_extractsAfterGroup() {
        let gid = UUID()
        var a = NoteBlock.image(UUID()); a.groupId = gid
        var b = NoteBlock.image(UUID()); b.groupId = gid
        let result = NoteBlock.shiftDown(blocks: [a, b], selId: b.id)
        #expect(result != nil)
        guard let r = result else { return }
        // b is last group member; extract to same position but standalone; a sole member → cleanup clears gid
        #expect(r[0].id == a.id); #expect(r[0].groupId == nil)
        #expect(r[1].id == b.id); #expect(r[1].groupId == nil)
    }

    @Test func shiftDown_standaloneWithGroupedBelow_mergesAtStart() {
        let gid = UUID()
        let a = NoteBlock.image(UUID())  // standalone
        var b = NoteBlock.image(UUID()); b.groupId = gid
        let result = NoteBlock.shiftDown(blocks: [a, b], selId: a.id)
        #expect(result != nil)
        guard let r = result else { return }
        #expect(r[0].groupId == gid); #expect(r[1].groupId == gid)
    }

    @Test func shiftDown_standaloneWithStandaloneBelow_createsGroup() {
        let a = NoteBlock.image(UUID())
        let b = NoteBlock.image(UUID())
        let result = NoteBlock.shiftDown(blocks: [a, b], selId: a.id)
        #expect(result != nil)
        guard let r = result else { return }
        #expect(r[0].groupId != nil); #expect(r[0].groupId == r[1].groupId)
    }

    @Test func shiftDown_standaloneWithTextBelow_swaps() {
        let img  = NoteBlock.image(UUID())
        let text = NoteBlock.text("T")
        let result = NoteBlock.shiftDown(blocks: [img, text], selId: img.id)
        #expect(result != nil)
        guard let r = result else { return }
        #expect(r[0].id == text.id); #expect(r[1].id == img.id)
    }

    @Test func shiftDown_atEnd_returnsNil() {
        let img = NoteBlock.image(UUID())
        #expect(NoteBlock.shiftDown(blocks: [img], selId: img.id) == nil)
    }

    // MARK: - NoteBlock.cleanupGroupIds

    @Test func cleanupGroupIds_soleGroupMember_clearsGroupId() {
        let gid = UUID()
        var img = NoteBlock.image(UUID()); img.groupId = gid
        var blocks = [img]
        NoteBlock.cleanupGroupIds(in: &blocks)
        #expect(blocks[0].groupId == nil)
    }

    @Test func cleanupGroupIds_multiMemberGroup_preservesGroupId() {
        let gid = UUID()
        var a = NoteBlock.image(UUID()); a.groupId = gid
        var b = NoteBlock.image(UUID()); b.groupId = gid
        var blocks = [a, b]
        NoteBlock.cleanupGroupIds(in: &blocks)
        #expect(blocks[0].groupId == gid)
        #expect(blocks[1].groupId == gid)
    }

    @Test func cleanupGroupIds_mixedGroups_onlyClearsLoneMembers() {
        let gid1 = UUID(); let gid2 = UUID()
        var a = NoteBlock.image(UUID()); a.groupId = gid1
        var b = NoteBlock.image(UUID()); b.groupId = gid1
        var c = NoteBlock.image(UUID()); c.groupId = gid2
        var blocks = [a, b, c]
        NoteBlock.cleanupGroupIds(in: &blocks)
        #expect(blocks[0].groupId == gid1)
        #expect(blocks[1].groupId == gid1)
        #expect(blocks[2].groupId == nil)
    }

    @Test func cleanupGroupIds_noGroups_noOp() {
        let text = NoteBlock.text("T")
        let img  = NoteBlock.image(UUID())
        var blocks = [text, img]
        NoteBlock.cleanupGroupIds(in: &blocks)
        #expect(blocks[0].groupId == nil)
        #expect(blocks[1].groupId == nil)
    }

    // MARK: - NoteBlock.computeGroups edge cases

    @Test func computeGroups_emptyArray_returnsEmpty() {
        #expect(NoteBlock.computeGroups(from: []).isEmpty)
    }

    @Test func computeGroups_allText_eachIsOwnGroup() {
        let a = NoteBlock.text("A")
        let b = NoteBlock.text("B")
        let groups = NoteBlock.computeGroups(from: [a, b])
        #expect(groups.count == 2)
        guard groups.count == 2 else { return }
        if case .text(let block, let idx) = groups[0].content {
            #expect(block.id == a.id); #expect(idx == 0)
        } else { Issue.record("groups[0] expected text") }
        if case .text(let block, let idx) = groups[1].content {
            #expect(block.id == b.id); #expect(idx == 1)
        } else { Issue.record("groups[1] expected text") }
    }

    @Test func computeGroups_groupIndices_correctForMidArrayGroup() {
        let gid = UUID()
        let text = NoteBlock.text("T")
        var imgA = NoteBlock.image(UUID()); imgA.groupId = gid
        var imgB = NoteBlock.image(UUID()); imgB.groupId = gid

        let groups = NoteBlock.computeGroups(from: [text, imgA, imgB])
        #expect(groups.count == 2)
        guard groups.count == 2 else { return }

        if case .images(_, let indices) = groups[1].content {
            #expect(indices == [1, 2])
            #expect(groups[1].firstBlockIndex == 1)
            #expect(groups[1].lastBlockIndex == 2)
        } else { Issue.record("groups[1] expected image group") }
    }

    // MARK: - NoteBlock backward-compat decoder

    @Test func decoder_withGroupId_roundTrips() throws {
        let gid = UUID()
        var block = NoteBlock.image(UUID())
        block.groupId = gid
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(NoteBlock.self, from: data)
        #expect(decoded.id == block.id)
        #expect(decoded.groupId == gid)
    }

    @Test func decoder_withoutGroupId_defaultsToNil() throws {
        let json = """
        {"id":"\(UUID().uuidString)","kind":"image","textContent":"","alignment":"center"}
        """
        let decoded = try JSONDecoder().decode(NoteBlock.self, from: json.data(using: .utf8)!)
        #expect(decoded.groupId == nil)
    }

    @Test func decoder_withoutAlignment_defaultsToCenter() throws {
        let json = """
        {"id":"\(UUID().uuidString)","kind":"text","textContent":"hello"}
        """
        let decoded = try JSONDecoder().decode(NoteBlock.self, from: json.data(using: .utf8)!)
        #expect(decoded.alignment == .center)
    }

    @Test func decoder_withoutTextContent_defaultsToEmpty() throws {
        let json = """
        {"id":"\(UUID().uuidString)","kind":"text"}
        """
        let decoded = try JSONDecoder().decode(NoteBlock.self, from: json.data(using: .utf8)!)
        #expect(decoded.textContent == "")
    }
}
