import SwiftUI

// A status control that replaces the old click-to-cycle behaviour: click the status icon and pick the
// target state directly. The label (the status icon) is caller-provided so each surface keeps its own
// look; the menu items + follow-up flow are shared. Follow-up lives here too (it's just a status):
// "Follow up…" opens FollowUpDateSheet; when already pending it offers change/clear.
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
            if task.status == .followUpPending {
                Button { showingFollowUp = true } label: { Label("Change follow-up date…", systemImage: "clock.arrow.circlepath") }
                Button(role: .destructive) { onBeforeChange?(); task.clearFollowUp() } label: {
                    Label("Clear follow-up", systemImage: "clock.badge.xmark")
                }
            } else {
                Button { showingFollowUp = true } label: { Label("Follow up…", systemImage: "clock.arrow.circlepath") }
            }
        } label: {
            label()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .sheet(isPresented: $showingFollowUp) {
            FollowUpDateSheet(
                initialDate: task.followUpAt ?? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now,
                onSave: { date in onBeforeChange?(); task.setFollowUp(date: date) },
                onRemove: task.status == .followUpPending ? { onBeforeChange?(); task.clearFollowUp() } : nil
            )
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
