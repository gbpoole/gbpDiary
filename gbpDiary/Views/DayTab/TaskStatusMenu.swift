import SwiftUI

// A status control that replaces the old click-to-cycle behaviour: click the status icon and pick the
// target state directly. The label (the status icon) is caller-provided so each surface keeps its own
// look; the menu items + follow-up flow are shared.
//
// Follow-up lives here too (it's just a status), as ONE item that always opens `FollowUpSheet`:
// "Follow up…" when none is pending, "Change follow-up" when one is. Nothing here clears a follow-up —
// **ending one is choosing another status**, and every other transition below already nulls `followUpAt`.
// This menu is also the only route into the sheet, so a follow-up is created in exactly one place.
struct TaskStatusMenu<Icon: View>: View {
    @Bindable var task: Task
    /// Runs just before a status change (e.g. TasksView keeps the row visible during re-filtering).
    var onBeforeChange: (() -> Void)? = nil
    @ViewBuilder var label: () -> Icon

    @State private var showingFollowUp = false

    var body: some View {
        Menu {
            statusItem("To do", "circle", .todo)
            statusItem("Started", "play.circle.fill", .started)
            statusItem("Completed", "checkmark.circle.fill", .completed)
            statusItem("Cancelled", "xmark.circle.fill", .cancelled)
            Divider()
            Button { showingFollowUp = true } label: {
                Label(task.status == .followUpPending ? "Change follow-up" : "Follow up…",
                      systemImage: "clock.arrow.circlepath")
            }
        } label: {
            label()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .sheet(isPresented: $showingFollowUp) {
            FollowUpSheet(task: task, onBeforeChange: onBeforeChange)
        }
    }

    // Current state shows a checkmark; others show the state's own icon.
    private func statusItem(_ title: String, _ icon: String, _ target: TaskStatus) -> some View {
        Button { setStatus(target) } label: {
            Label(title, systemImage: task.status == target ? "checkmark" : icon)
        }
    }

    // Jump directly to a state, reusing the existing transition methods so timestamps stay correct.
    private func setStatus(_ target: TaskStatus) {
        guard task.status != target else { return }
        onBeforeChange?()
        let now = Date()
        switch target {
        case .todo:
            switch task.status {
            case .completed:       task.unmarkCompleted()
            case .cancelled:       task.unmarkCancelled()
            case .followUpPending: task.followUpAt = nil; task.status = .todo; task.updatedAt = now
            default:               task.status = .todo; task.updatedAt = now
            }
        case .started:
            if task.status == .completed { task.unmarkCompleted() }
            else if task.status == .cancelled { task.unmarkCancelled() }
            task.followUpAt = nil
            task.status = .started
            task.updatedAt = now
        case .completed:
            if task.status == .cancelled { task.unmarkCancelled() }
            task.followUpAt = nil
            task.markCompleted()
        case .cancelled:
            task.markCancelled()
        case .followUpPending:
            showingFollowUp = true   // needs a date
        }
    }
}
