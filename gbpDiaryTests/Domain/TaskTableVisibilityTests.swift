import Foundation
import Testing
@testable import gbpDiary

struct TaskTableVisibilityTests {

    private func hidden(isOpen: Bool = true, needsTriage: Bool = false, isWaiting: Bool = false,
                        isStanding: Bool = false, showWaiting: Bool = false,
                        showStanding: Bool = false) -> Bool {
        TaskTableVisibility.isHidden(isOpen: isOpen, needsTriage: needsTriage, isWaiting: isWaiting,
                                     isStanding: isStanding, showWaiting: showWaiting,
                                     showStanding: showStanding)
    }

    @Test func ordinaryReviewedTask_isShown() {
        #expect(!hidden())
    }

    @Test func untriagedOpenTask_isHidden_butClosedOneIsNot() {
        #expect(hidden(needsTriage: true))
        // No point triaging something already done, so a closed task is never hidden for triage.
        #expect(!hidden(isOpen: false, needsTriage: true))
    }

    @Test func waitingTask_hiddenUntilItsFilterIsOn() {
        #expect(hidden(isWaiting: true))
        #expect(!hidden(isWaiting: true, showWaiting: true))
    }

    @Test func standingTask_hiddenUntilItsFilterIsOn() {
        #expect(hidden(isStanding: true))
        #expect(!hidden(isStanding: true, showStanding: true))
    }

    /// The reveals are independent: showing waiting work must not drag standing work in with it.
    @Test func revealsAreIndependent() {
        #expect(hidden(isStanding: true, showWaiting: true))
        #expect(hidden(isWaiting: true, showStanding: true))
        #expect(!hidden(isWaiting: true, isStanding: true, showWaiting: true, showStanding: true))
    }

    /// Triage hiding wins regardless of the flag filters — the inbox is a separate surface.
    @Test func untriagedStaysHidden_evenWhenItsOtherFlagsAreRevealed() {
        #expect(hidden(needsTriage: true, isStanding: true, showStanding: true))
    }
}
