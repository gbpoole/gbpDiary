import SwiftUI
import SwiftData

// Pick a link target for a note-to-note link. The user chooses among three kinds — Content notes,
// Diary notes, and Meetings — via a segmented control. Everything resolves to a target *note* id
// (a meeting resolves to its minutes note, created if needed), so links are uniformly `note://…`.
// Used for both inserting a new link and editing an existing one (edit mode adds a Remove action
// and preselects the current target's kind).
struct LinkPickerSheet: View {
    enum Mode: Equatable {
        case insert
        case edit(currentNoteID: UUID)
    }

    let mode: Mode
    var onPick: (UUID) -> Void
    var onRemove: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allNotes: [Note]
    @Query(sort: \Minutes.meetingAt, order: .reverse) private var allMinutes: [Minutes]
    @Query(sort: \Project.name) private var allProjects: [Project]

    @State private var kind: LinkKind = .content
    @State private var selectedNote: Note?
    @State private var selectedMinutes: Minutes?

    private enum LinkKind: String, CaseIterable, Identifiable {
        case content = "Content"
        case diary = "Diary"
        case meeting = "Meetings"
        var id: String { rawValue }
    }

    // The note being edited (excluded from the target lists so it can't link to itself).
    private var currentNoteID: UUID? {
        if case .edit(let id) = mode { return id }
        return nil
    }

    private var contentNotes: [Note] {
        allNotes.filter { $0.isContentNote && $0.id != currentNoteID }
    }
    private var diaryNotes: [Note] {
        allNotes.filter { $0.dayRecord != nil && !$0.title.isEmpty && $0.id != currentNoteID }
    }
    private var meetings: [Minutes] {
        allMinutes.filter { $0.note?.id != currentNoteID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Kind", selection: $kind) {
                        ForEach(LinkKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch kind {
                    case .content: notePicker(contentNotes, empty: "No content notes")
                    case .diary:   notePicker(diaryNotes, empty: "No titled diary notes")
                    case .meeting: meetingPicker
                    }

                    if onRemove != nil {
                        Divider()
                        Button(role: .destructive) { onRemove?(); dismiss() } label: {
                            Label("Remove Link", systemImage: "trash")
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(mode == .insert ? "Insert Link" : "Edit Link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .insert ? "Insert" : "Save") { confirm() }
                        .disabled(!canConfirm)
                }
            }
        }
        .onAppear(perform: preselect)
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private func notePicker(_ notes: [Note], empty: String) -> some View {
        let tags = Set(notes.flatMap(\.tags)).sorted()
        let tagFilters = tags.map { tag in
            PickerFilter<Note>(id: "tag.\(tag)", label: tag, chipColor: AppTheme.tag, group: "Tag") {
                $0.tags.contains(tag)
            }
        }
        return Group {
            if notes.isEmpty {
                Text(empty).foregroundStyle(.secondary).font(.callout)
            } else {
                FuzzyPickerField(
                    allItems: notes,
                    selectedItem: $selectedNote,
                    label: { noteLabel($0) },
                    chipColor: AppTheme.project,
                    placeholder: "Search notes…",
                    tapArea: true,
                    emptyLabel: "Tap to choose a note",
                    filters: tagFilters.isEmpty ? nil : tagFilters
                )
            }
        }
    }

    private var meetingPicker: some View {
        let projectFilters = allProjects.map { p in
            PickerFilter<Minutes>(id: "project.\(p.id)", label: p.name, chipColor: AppTheme.project, group: "Project") {
                $0.projects.contains(where: { $0.id == p.id })
            }
        }
        return Group {
            if meetings.isEmpty {
                Text("No meetings").foregroundStyle(.secondary).font(.callout)
            } else {
                FuzzyPickerField(
                    allItems: meetings,
                    selectedItem: $selectedMinutes,
                    label: { meetingLabel($0) },
                    chipColor: AppTheme.project,
                    placeholder: "Search meetings…",
                    tapArea: true,
                    emptyLabel: "Tap to choose a meeting",
                    filters: projectFilters.isEmpty ? nil : projectFilters
                )
            }
        }
    }

    private func noteLabel(_ note: Note) -> String {
        let title = note.title.isEmpty ? "Untitled" : note.title
        if let day = note.dayRecord {
            return "\(title) — \(day.date.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
        return title
    }

    private func meetingLabel(_ minutes: Minutes) -> String {
        let summary = minutes.summary?.isEmpty == false ? minutes.summary! : "Meeting"
        return "\(summary) — \(minutes.meetingAt.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private var canConfirm: Bool {
        switch kind {
        case .content, .diary: return selectedNote != nil
        case .meeting:         return selectedMinutes != nil
        }
    }

    private func confirm() {
        switch kind {
        case .content, .diary:
            if let note = selectedNote { onPick(note.id) }
        case .meeting:
            if let minutes = selectedMinutes { onPick(noteID(forMeeting: minutes)) }
        }
        dismiss()
    }

    // A meeting links to its minutes note; create it if the meeting doesn't have one yet. We link by
    // the note's `id` (a stable UUID assigned at init), so no save is needed here — an explicit save
    // would re-render the editor mid-insert and swallow the insertion.
    private func noteID(forMeeting minutes: Minutes) -> UUID {
        if let existing = minutes.note { return existing.id }
        let note = Note(content: "")
        modelContext.insert(note)
        minutes.note = note
        minutes.updatedAt = Date()
        return note.id
    }

    private func preselect() {
        guard case .edit(let id) = mode else { return }
        if let minutes = allMinutes.first(where: { $0.note?.id == id }) {
            kind = .meeting
            selectedMinutes = minutes
        } else if let note = allNotes.first(where: { $0.id == id }) {
            kind = note.dayRecord != nil ? .diary : .content
            selectedNote = note
        }
    }
}
