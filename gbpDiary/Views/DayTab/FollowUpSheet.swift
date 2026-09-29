import SwiftUI

/// The follow-up modal — the **only** way a follow-up is created or re-dated, reached from
/// `TaskStatusMenu` ("Follow up…" when none is pending, "Change follow-up" when one is).
///
/// It shows the history read-only and offers **two explicit verbs**:
/// - **Add another follow-up** — appends an entry and moves `followUpAt`. Chasing a second time is a new
///   entry, not an edit, so "I have pushed this three times" stays recoverable.
/// - **Correct last entry** — offered only while a follow-up is pending, and only for that entry: a
///   pending follow-up is a live intention, so fixing it isn't rewriting the record.
///
/// Correcting anything older, or removing an entry, is deliberately *not* here — that lives in the
/// editable Follow-ups list on `TaskDetailView`.
struct FollowUpSheet: View {
    @Bindable var task: Task
    /// Runs just before the write (e.g. `TasksView` keeps a re-filtered row visible).
    var onBeforeChange: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private enum Verb: String, CaseIterable, Identifiable {
        case add = "Add another follow-up"
        case correct = "Correct last entry"
        var id: String { rawValue }
    }

    @State private var verb: Verb = .add
    @State private var date: Date = FollowUpHistory.day(Date().addingTimeInterval(86_400))
    @State private var note: String = ""

    /// Only the live follow-up may be corrected here; nil means Add is the only verb.
    private var pending: FollowUpEntry? { task.pendingFollowUpEntry }
    private var history: [FollowUpEntry] { FollowUpHistory.displayOrder(task.followedUpHistory) }
    private var canSave: Bool { FollowUpHistory.canSave(note: note, date: date) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if pending != nil {
                        GroupBox {
                            Picker("", selection: $verb) {
                                ForEach(Verb.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    GroupBox(verb == .correct ? "Correct the pending follow-up" : "New follow-up") {
                        VStack(alignment: .leading, spacing: 10) {
                            // Day granularity only — a follow-up is a day, never a time — and never the past.
                            DatePicker("Follow up on", selection: $date,
                                       in: FollowUpHistory.day(Date())...,
                                       displayedComponents: .date)
                            TextField("Why — e.g. waiting on Sam's reply", text: $note, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !history.isEmpty {
                        GroupBox("Follow-ups so far (\(history.count))") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(history) { entry in historyRow(entry) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(pending == nil ? "Follow Up" : "Change Follow-up")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(verb == .correct ? "Save" : "Add") { save() }.disabled(!canSave)
                }
            }
        }
        .onAppear(perform: seed)
        .onChange(of: verb) { _, _ in seed() }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 400)
        #endif
    }

    /// Correcting starts from the pending entry; adding starts from tomorrow with an empty reason (the
    /// note is the point of the record, so it is never pre-filled from an older entry).
    private func seed() {
        if verb == .correct, let pending {
            date = pending.date
            note = pending.note
        } else {
            date = FollowUpHistory.day(Date().addingTimeInterval(86_400))
            note = ""
        }
    }

    private func save() {
        onBeforeChange?()
        if verb == .correct, let pending {
            task.updateFollowUp(entryID: pending.id, date: date, note: note)
        } else {
            task.setFollowUp(date: date, note: note)
        }
        dismiss()
    }

    @ViewBuilder private func historyRow(_ entry: FollowUpEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .foregroundStyle(AppTheme.mutedText).font(.system(size: 12))
                .frame(width: 18).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    if entry.id == pending?.id {
                        Chip(label: task.isFollowUpDue ? "due" : "pending",
                             color: task.isFollowUpDue ? AppTheme.destructive : AppTheme.mutedText)
                    }
                }
                if !entry.note.isEmpty {
                    Text(entry.note).font(.caption).foregroundStyle(AppTheme.mutedText)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
