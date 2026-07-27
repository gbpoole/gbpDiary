import SwiftUI
import SwiftData

struct NoteEditorSheet: View {
    @Bindable var note: Note
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query private var allNotes: [Note]
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var title = ""
    @State private var selectedProject: Project?
    @State private var selectedTags: [TagItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Title") {
                        TextField("Note title (optional)", text: $title)
                            .textFieldStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Project") {
                        FuzzyPickerField(
                            allItems: allProjects,
                            selectedItem: $selectedProject,
                            label: { $0.name },
                            chipColor: AppTheme.project,
                            tapArea: true,
                            emptyLabel: "None — tap to link project"
                        )
                    }
                    GroupBox("Tags") {
                        FuzzyPickerField(
                            allItems: availableTags,
                            selected: $selectedTags,
                            label: { $0.id },
                            chipColor: AppTheme.tag,
                            placeholder: "Search tags…",
                            onCreateItem: { TagItem(id: $0) },
                            tapArea: true,
                            emptyLabel: "None — tap to add tags"
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Note Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
        .onAppear {
            title = note.title
            selectedProject = note.project
            selectedTags = note.tags.map { TagItem(id: $0) }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 280)
        #endif
    }

    private var availableTags: [TagItem] {
        var seen = Set<String>()
        var result: [TagItem] = []
        let all = allNotes.flatMap(\.tags) + allProjects.flatMap(\.tags) + allPeople.flatMap(\.tags)
        for tag in all.sorted() where seen.insert(tag).inserted {
            result.append(TagItem(id: tag))
        }
        return result
    }

    private func save() {
        note.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        note.project = selectedProject
        note.tags = selectedTags.map(\.id)
        note.updatedAt = Date()
        dismiss()
    }
}

private struct TagItem: Identifiable {
    let id: String
}
