import Testing
@testable import gbpDiary

@Suite("TaskEditorValidation")
struct TaskEditorValidationTests {
    @Test func blankSummary_cannotSave() {
        #expect(!TaskEditorValidation.canSave(summary: "   ", hasProject: true, requireProject: false,
                                              hasAssignee: true, requireAssignee: false))
    }

    @Test func nonBlankSummary_noRequirements_canSave() {
        #expect(TaskEditorValidation.canSave(summary: "Write report", hasProject: false, requireProject: false,
                                             hasAssignee: false, requireAssignee: false))
    }

    @Test func requireProject_blocksUntilProjectChosen() {
        #expect(!TaskEditorValidation.canSave(summary: "x", hasProject: false, requireProject: true,
                                              hasAssignee: false, requireAssignee: false))
        #expect(TaskEditorValidation.canSave(summary: "x", hasProject: true, requireProject: true,
                                             hasAssignee: false, requireAssignee: false))
    }

    @Test func requireAssignee_blocksUntilAssigneeChosen() {
        #expect(!TaskEditorValidation.canSave(summary: "x", hasProject: true, requireProject: false,
                                              hasAssignee: false, requireAssignee: true))
        #expect(TaskEditorValidation.canSave(summary: "x", hasProject: true, requireProject: false,
                                             hasAssignee: true, requireAssignee: true))
    }

    @Test func bothRequirements_needBoth() {
        #expect(!TaskEditorValidation.canSave(summary: "x", hasProject: true, requireProject: true,
                                              hasAssignee: false, requireAssignee: true))
        #expect(TaskEditorValidation.canSave(summary: "x", hasProject: true, requireProject: true,
                                             hasAssignee: true, requireAssignee: true))
    }
}
