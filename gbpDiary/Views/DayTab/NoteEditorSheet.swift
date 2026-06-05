import SwiftUI
import SwiftData

struct NoteEditorSheet: View {
    @Bindable var note: Note
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.name) private var allProjects: [Project]

    @State private var selectedProject: Project?
    @State private var tagsText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Project", selection: $selectedProject) {
                    Text("None").tag(Optional<Project>.none)
                    ForEach(allProjects) { p in
                        Text(p.name).tag(Optional(p))
                    }
                }
                Section("Tags") {
                    TextField("Comma-separated tags", text: $tagsText)
                }
            }
            .navigationTitle("Note Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
        .onAppear {
            selectedProject = note.project
            tagsText = note.tags.joined(separator: ", ")
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 240)
        #endif
    }

    private func save() {
        note.project = selectedProject
        note.tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        note.updatedAt = Date()
        dismiss()
    }
}
