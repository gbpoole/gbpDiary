import SwiftUI
import SwiftData

// Creation modal for a Content note: set a (required) title, optional tags and project, then create
// the note and open it in a new tab ready to edit. Presented from the Content list "+" and the
// sidebar "New Note" button. When `note` is non-nil it edits that note's metadata in place instead.
struct ContentNoteEditorSheet: View {
    var note: Note? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceModel.self) private var workspace

    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query private var allNotes: [Note]
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var title = ""
    @State private var selectedProject: Project?
    @State private var selectedTags: [ContentTagItem] = []

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Title") {
                        TextField("Note title", text: $title)
                            .textFieldStyle(.plain)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Tags") {
                        FuzzyPickerField(
                            allItems: availableTags,
                            selected: $selectedTags,
                            label: { $0.id },
                            chipColor: AppTheme.tag,
                            placeholder: "Search tags…",
                            onCreateItem: { ContentTagItem(id: $0) },
                            tapArea: true,
                            emptyLabel: "None — tap to add tags"
                        )
                    }
                    GroupBox("Project (optional)") {
                        FuzzyPickerField(
                            allItems: allProjects,
                            selectedItem: $selectedProject,
                            label: { $0.name },
                            chipColor: AppTheme.project,
                            tapArea: true,
                            emptyLabel: "None — tap to link project"
                        )
                    }
                }
                .padding()
            }
            .navigationTitle(note == nil ? "New Content Note" : "Edit Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(note == nil ? "Create" : "Save") { save() }
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear {
            if let note {
                title = note.title
                selectedProject = note.project
                selectedTags = note.tags.map { ContentTagItem(id: $0) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 320)
        #endif
    }

    private var availableTags: [ContentTagItem] {
        var seen = Set<String>()
        var result: [ContentTagItem] = []
        let all = allNotes.flatMap(\.tags) + allProjects.flatMap(\.tags) + allPeople.flatMap(\.tags)
        for tag in all.sorted() where seen.insert(tag).inserted {
            result.append(ContentTagItem(id: tag))
        }
        return result
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tags = selectedTags.map(\.id)
        if let note {
            note.title = trimmed
            note.project = selectedProject
            note.tags = tags
            note.updatedAt = Date()
            dismiss()
        } else {
            let newNote = Note(content: "", title: trimmed)
            newNote.project = selectedProject
            newNote.tags = tags
            modelContext.insert(newNote)
            // Persist before opening the tab so the note has a permanent persistentModelID and
            // stable backing data — otherwise a later autosave reassigns the temporary id and
            // invalidates the instance the tab resolved (crashes on next property access).
            try? modelContext.save()
            let id = newNote.persistentModelID
            dismiss()
            workspace.openContentForEditing(id)
        }
    }
}
