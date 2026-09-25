import SwiftUI
import SwiftData

// The batch half of the hybrid breakdown workflow: type or paste an indented outline and get a task
// subtree. Parsing is `TaskOutlineParser`, creation is `TaskBreakdown` — this view is just the input.
//
// Shared on purpose: TaskDetailView uses it today and the Phase C curation stepper will reuse it.
struct TaskBreakdownField: View {
    /// Parent to hang the new tasks under. Nil creates top-level tasks (fresh capture → Inbox).
    var parent: Task?
    /// Overrides the project inherited from `parent` (used where there is no parent to inherit from).
    var project: Project?
    var onCreated: ([Task]) -> Void = { _ in }
    /// Where the unsaved outline lives. Callers that must survive their view being torn down (e.g. the
    /// task tab, which is rebuilt on every tab switch) pass storage that outlives the view.
    @Binding var text: String
    /// Starts opened — used where the field is part of a form rather than a disclosure.
    var alwaysOpen: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var isOpenState = false
    @FocusState private var isFocused: Bool

    private var isOpen: Bool { alwaysOpen || isOpenState }

    private var parsed: [OutlineNode] { TaskOutlineParser.parse(text) }
    private var canAdd: Bool { !parsed.isEmpty }

    /// Total nodes, so the button can say how many tasks will actually be created.
    private var plannedCount: Int {
        func count(_ nodes: [OutlineNode]) -> Int {
            nodes.reduce(0) { $0 + 1 + count($1.children) }
        }
        return count(parsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isOpen {
                editor
            } else {
                Button {
                    isOpenState = true
                    isFocused = true
                } label: {
                    // Signal a kept draft so it is not silently forgotten behind the collapsed control.
                    Label(text.isEmpty ? "Break down…" : "Break down… (draft)",
                          systemImage: "list.bullet.indent")
                        .font(AppTheme.bodyFont(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $text)
                .font(AppTheme.bodyFont(size: 13))
                .frame(minHeight: 72, maxHeight: 160)
                .padding(4)
                .background(AppTheme.cardRaised.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.mutedText.opacity(0.3)))
                .focused($isFocused)

            Text("One task per line. Indent with Tab or four spaces to make a subtask.")
                .font(AppTheme.bodyFont(size: 11))
                .foregroundStyle(AppTheme.mutedText)

            HStack(spacing: 8) {
                Button("Add \(plannedCount) task\(plannedCount == 1 ? "" : "s")") { commit() }
                    .disabled(!canAdd)
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Cancel") { collapse() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.mutedText)
                Spacer()
            }
            .font(AppTheme.bodyFont(size: 12))
        }
    }

    private func commit() {
        let created = TaskBreakdown.create(parsed, under: parent, project: project, in: modelContext)
        guard !created.isEmpty else { return }
        onCreated(created)
        text = ""
        collapse()
    }

    /// Cancel leaves `text` alone — the draft is deliberately kept so it survives coming back later.
    private func collapse() {
        isOpenState = false
        isFocused = false
    }
}
