import SwiftUI
import SwiftData

// Identifiable wrapper so free-form tag strings can flow through FuzzyPickerField. Shared across the
// Content views.
struct ContentTagItem: Identifiable { let id: String }

// Browse list of free-standing "Content" vault notes (any Note with a title). Mirrors the other
// list pages: a shared FilterBar (Tag / Project groups) + a Tasks-style table; a row opens the
// note in its own workspace tab.
struct ContentListView: View {
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Environment(WorkspaceModel.self) private var workspace

    @State private var activeFilterIds: Set<String> = []
    @State private var showingAdd = false

    private var contentNotes: [Note] { allNotes.filter(\.isContentNote) }

    private var noteFilters: [PickerFilter<Note>] {
        let tags = Set(contentNotes.flatMap(\.tags)).sorted()
        let tagGroup = tags.map { tag in
            PickerFilter<Note>(id: "tag.\(tag)", label: tag, chipColor: AppTheme.tag, group: "Tag") {
                $0.tags.contains(tag)
            }
        }
        let projectGroup = allProjects.map { p in
            PickerFilter<Note>(id: "project.\(p.id)", label: p.name, chipColor: AppTheme.project, group: "Project") {
                $0.project?.id == p.id
            }
        }
        return tagGroup + projectGroup
    }

    private var filteredNotes: [Note] {
        FilterEngine.apply(contentNotes, filters: noteFilters, activeIds: activeFilterIds)
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(
                filters: noteFilters,
                activeFilterIds: $activeFilterIds,
                onClearAll: { activeFilterIds = [] }
            )
            Divider()
            noteTable
        }
        .navigationTitle("Content")
        .toolbar {
            ToolbarItem {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) { ContentNoteEditorSheet(note: nil) }
    }

    private func open(_ note: Note) {
        workspace.openInNewTab(.contentNote(note.persistentModelID))
    }

    #if os(macOS)
    private var noteTable: some View {
        Table(filteredNotes) {
            TableColumn("Title") { note in
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .lineLimit(1)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.text)
                    .onTapGesture { open(note) }
            }
            TableColumn("Tags") { note in
                Text(note.tags.joined(separator: ", "))
                    .foregroundStyle(AppTheme.tag)
                    .lineLimit(1)
            }
            .width(180)
            TableColumn("Project") { note in
                Text(note.project?.name ?? "")
                    .foregroundStyle(AppTheme.project)
                    .lineLimit(1)
            }
            .width(160)
            TableColumn("Updated") { note in
                Text(note.updatedAt, format: .dateTime.month(.abbreviated).day().year())
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(100)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
    }
    #else
    private var noteTable: some View {
        List(filteredNotes) { note in
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Untitled" : note.title).font(.subheadline.bold())
                if !note.tags.isEmpty {
                    Text(note.tags.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .onTapGesture { open(note) }
        }
    }
    #endif
}
