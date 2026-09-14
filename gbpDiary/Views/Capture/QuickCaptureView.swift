import SwiftUI
import SwiftData

// The lightweight window shown when a `gbpdiary://task?…` capture arrives (from Alfred/Shortcuts). Prefilled
// from the URL; you confirm the summary + optional project/due. The created task ALWAYS lands in the Inbox
// (`needsTriage = true`, from Task.init) — the review gate always fires — and carries a first-class TaskSource
// linking back to where it came from.
struct QuickCaptureView: View {
    let request: CaptureURL.Request
    // Called after Add/Cancel to close the host panel (the AppKit capture window isn't a sheet).
    var onFinish: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]
    @Query private var allTasks: [Task]
    @Query private var allEmails: [EmailMessage]

    @State private var summary = ""
    @State private var project: Project?
    @State private var dueOn = false
    @State private var dueDate = Date()
    @FocusState private var summaryFocused: Bool

    private var canSave: Bool { !summary.trimmingCharacters(in: .whitespaces).isEmpty }

    // Warn (don't block) if an open task already links to this exact source URL — avoids silent duplicates.
    private var duplicate: Task? {
        guard let url = request.url else { return nil }
        return allTasks.first { $0.isOpen && $0.source?.url == url }
    }

    private var resolvedEmail: EmailMessage? {
        guard request.kind == .email, let mid = request.mailId else { return nil }
        return allEmails.first { $0.messageId == mid }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Task") {
                        TextField("What needs doing?", text: $summary, axis: .vertical)
                            .textFieldStyle(.roundedBorder).lineLimit(1...4)
                            .focused($summaryFocused)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Project") {
                        FuzzyPickerField(allItems: allProjects, selectedItem: $project, label: { $0.name },
                                         chipColor: AppTheme.project, tapArea: true,
                                         emptyLabel: "None — tap to choose")
                    }
                    GroupBox("Due") {
                        HStack {
                            Toggle("Due date", isOn: $dueOn)
                            if dueOn {
                                DatePicker("", selection: $dueDate, displayedComponents: .date).labelsHidden()
                            }
                            Spacer()
                        }
                    }
                    GroupBox("Source") { sourceRow }
                    if let dup = duplicate {
                        Label("An open task already links to this source: \(dup.summary)", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(AppTheme.followUp)
                    }
                }
                .padding()
            }
            Divider()
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { onFinish() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            .padding()
        }
        .onAppear { summary = request.title ?? ""; summaryFocused = true }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 340)
        #endif
    }

    private var sourceRow: some View {
        HStack(spacing: 8) {
            Image(systemName: request.kind.systemImage).foregroundStyle(AppTheme.mutedText)
            Text(request.title ?? request.url ?? request.kind.displayName)
                .lineLimit(1).foregroundStyle(AppTheme.mutedText)
            Spacer(minLength: 0)
            Text(request.kind.displayName).font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func add() {
        let email = resolvedEmail
        let source = TaskSource(kind: request.kind, url: request.url, title: request.title, email: email)
        let task = Task(summary: summary.trimmingCharacters(in: .whitespaces))
        task.project = project
        task.dueAt = dueOn ? dueDate : nil
        // Assign to "Me" (like the diary quick-add) so the capture shows in the diary "My Active Tasks → Inbox".
        task.assignee = allPeople.first { $0.id == AppSettingsStore.myPersonID }
        if let email { task.originEmail = email }   // keep the email backbone consistent
        modelContext.insert(source)
        modelContext.insert(task)
        task.source = source                        // needsTriage stays true → lands in the Inbox
        try? modelContext.save()
        onFinish()
    }
}
