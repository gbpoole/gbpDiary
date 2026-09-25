import Foundation
import Testing
@testable import gbpDiary

struct TaskTableVisibilityTests {

    private func hidden(isOpen: Bool = true, needsTriage: Bool = false, isWaiting: Bool = false,
                        isStanding: Bool = false, showWaiting: Bool = false,
                        showStanding: Bool = false, showNeedsTriage: Bool = false) -> Bool {
        TaskTableVisibility.isHidden(isOpen: isOpen, needsTriage: needsTriage, isWaiting: isWaiting,
                                     isStanding: isStanding, showWaiting: showWaiting,
                                     showStanding: showStanding, showNeedsTriage: showNeedsTriage)
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

    /// Triage hiding yields only to its OWN filter: revealing waiting or standing work does not drag
    /// the inbox in with it.
    @Test func untriagedStaysHidden_whenOnlyOtherFlagsAreRevealed() {
        #expect(hidden(needsTriage: true, isStanding: true, showStanding: true))
        #expect(hidden(needsTriage: true, isWaiting: true, showWaiting: true))
    }

    /// The route a fresh capture takes to the planning board: reveal it here, then place it (which
    /// marks it reviewed).
    @Test func untriagedTask_revealedByItsOwnFilter() {
        #expect(hidden(needsTriage: true))
        #expect(!hidden(needsTriage: true, showNeedsTriage: true))
    }

    /// Revealing the inbox must not also drag in waiting or standing work.
    @Test func needsTriageReveal_doesNotRevealTheOtherHiddenKinds() {
        #expect(hidden(isWaiting: true, showNeedsTriage: true))
        #expect(hidden(isStanding: true, showNeedsTriage: true))
    }
}
