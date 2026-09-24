import SwiftUI
import SwiftData

// Tab content for a single free-standing "Content" note: a compact metadata header (Title / Tags /
// Project) styled like the meeting-minutes header, the markdown editor (with note-link chips and an
// insert-link picker), and a "Linked from" backlinks panel.
struct ContentNoteDetailView: View {
    @Bindable var note: Note
    var asSheet: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace
    @Query private var allNotes: [Note]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var titleDraft = ""
    @State private var titleDebouncer = Debouncer()

    var body: some View {
        // The model can be deleted while this view is still mounted (its tab is closed, but
        // the view renders once more in the same pass; a sheet is not a tab at all). Reading a
        // deleted model's stored properties traps, so bail out before the content is built.
        if note.isDeletedOrDetached {
            DeletedEntityPlaceholder(noun: "note")
        } else {
            Group {
                if asSheet {
                VStack(alignment: .leading, spacing: 12) { header }.padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        editor
                        backlinksSection
                    }
                    .padding()
                }
            }
        }
            .navigationTitle(note.title.isEmpty ? "Untitled" : note.title)
            .onAppear { titleDraft = note.title }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .onChange(of: titleDraft) { _, newValue in
                    titleDebouncer.schedule(delay: 0.6) {
                        note.title = newValue
                        note.updatedAt = Date()
                    }
                }
            VStack(alignment: .leading, spacing: 7) {
                metaRow("Tags")    { tagsField }
                metaRow("Project") { projectField }
            }
            .padding(10)
            .background(AppTheme.cardRaised.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func metaRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 22)
    }

    private var tagsField: some View {
        FuzzyPickerField(
            allItems: availableTags,
            selected: Binding(
                get: { note.tags.map { ContentTagItem(id: $0) } },
                set: { note.tags = $0.map(\.id); note.updatedAt = Date() }
            ),
            label: { $0.id },
            chipColor: AppTheme.tag,
            placeholder: "Search tags…",
            onCreateItem: { ContentTagItem(id: $0) },
            tapArea: true,
            emptyLabel: "None — tap to add tags"
        )
    }

    private var projectField: some View {
        FuzzyPickerField(
            allItems: allProjects,
            selectedItem: Binding<Project?>(
                get: { note.project },
                set: { note.project = $0; note.updatedAt = Date() }
            ),
            label: { $0.name },
            chipColor: AppTheme.project,
            onCreateItem: { makeProject($0) },
            tapArea: true,
            emptyLabel: "None — tap to link project"
        )
    }

    // Create a new Project on the fly while linking one (auto-selected).
    private func makeProject(_ projectName: String) -> Project? {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let project = Project(name: trimmed)
        modelContext.insert(project)
        return project
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

    // MARK: - Editor

    private var editor: some View {
        MarkdownDocumentEditor(
            note: note,
            startInEdit: workspace.autoEditContentId == note.persistentModelID,
            onStartedEditing: { workspace.autoEditContentId = nil },
            showsHeader: false
        )
    }

    // MARK: - Backlinks

    private var backlinkNotes: [Note] {
        let ids = NoteLinkUsageScanner.backlinks(to: note.id, in: allNotes.map { (id: $0.id, content: $0.content) })
        return ids.compactMap { id in allNotes.first { $0.id == id } }
    }

    @ViewBuilder
    private var backlinksSection: some View {
        let backlinks = backlinkNotes
        if !backlinks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Linked from")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(backlinks) { source in
                    Button {
                        workspace.focusOrOpen(.contentNote(source.persistentModelID))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "link").font(.caption2)
                            Text(source.title.isEmpty ? "Untitled" : source.title).font(.callout)
                        }
                        .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(AppTheme.cardRaised.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
