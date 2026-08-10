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
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace

    @State private var showingAdd = false
    // @Model exposes `id: UUID` (its @Attribute), so the Table's selection is keyed by UUID.
    @State private var selection: Set<UUID> = []
    @State private var stashedSelection: Set<UUID> = []
    @State private var confirmingBulkDelete = false

    // Filter/search/sort live on the active tab (persisted + remembered across tab switches).
    private var filter: ListPageFilter { workspace.active.pageFilter(for: .content) }
    private static let sortColumns: [SortColumn<Note>] = [
        SortColumn("title", \.titleKey), SortColumn("tags", \.tagsKey),
        SortColumn("project", \.projectKey), SortColumn("updated", \.updatedAt),
    ]
    private var sortOrderBinding: Binding<[KeyPathComparator<Note>]> {
        let f = filter
        return Binding(
            get: { TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "updated") },
            set: { if let d = TableSortPersistence.descriptor(for: $0, columns: Self.sortColumns) { f.sortColumnID = d.id; f.sortAscending = d.ascending } }
        )
    }

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

    private var rows: [Note] {
        let f = filter
        let matched = FilterEngine.apply(contentNotes, filters: noteFilters, activeIds: f.activeFilterIds)
        let query = f.searchText.trimmingCharacters(in: .whitespaces)
        let searched = query.isEmpty ? matched : matched.filter { FuzzyMatch.matches(query, in: searchHaystack($0)) }
        return searched.sorted(using: TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "updated"))
    }

    private func searchHaystack(_ n: Note) -> String {
        [n.title, n.project?.name, n.tags.joined(separator: " ")]
            .compactMap { $0 }.joined(separator: " ")
    }

    private var selectedNotes: [Note] {
        contentNotes.filter { selection.contains($0.id) }
    }

    private func clearSelection() { selection.removeAll(); stashedSelection.removeAll() }

    private func bulkDelete() {
        for n in selectedNotes {
            workspace.closeEntity(n.persistentModelID)
            modelContext.delete(n)
        }
        clearSelection()
    }

    var body: some View {
        @Bindable var f = filter
        return VStack(spacing: 0) {
            ListToolbar(
                searchText: $f.searchText,
                searchPrompt: "Search content…",
                filters: noteFilters,
                activeFilterIds: $f.activeFilterIds,
                onClearAll: { f.activeFilterIds = [] }
            )
            BulkActionBar(count: selection.count, onClear: { clearSelection() }) {
                Button("Delete", role: .destructive) { confirmingBulkDelete = true }
            }
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
        .alert("Delete \(selection.count) note\(selection.count == 1 ? "" : "s")?", isPresented: $confirmingBulkDelete) {
            Button("Delete", role: .destructive) { bulkDelete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes the selected note\(selection.count == 1 ? "" : "s"). Related items are unlinked, not deleted.") }
        .onChange(of: Set(rows.map(\.id))) { _, visible in
            let result = TableSelectionReconcile.reconcile(selection: selection, stashed: stashedSelection, visible: visible)
            if result.selection != selection { selection = result.selection }
            if result.stashed != stashedSelection { stashedSelection = result.stashed }
        }
    }

    private func open(_ note: Note) {
        workspace.openInNewTab(.contentNote(note.persistentModelID))
    }

    #if os(macOS)
    private var noteTable: some View {
        Table(rows, selection: $selection, sortOrder: sortOrderBinding) {
            TableColumn("Title", value: \.titleKey) { note in
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .lineLimit(1)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.text)
            }
            .width(min: 160, ideal: 260)
            TableColumn("Tags", value: \.tagsKey) { note in
                Text(note.tags.joined(separator: ", "))
                    .foregroundStyle(AppTheme.tag)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 180)
            TableColumn("Project", value: \.projectKey) { note in
                Text(note.project?.name ?? "")
                    .foregroundStyle(AppTheme.project)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 160)
            TableColumn("Updated", value: \.updatedAt) { note in
                Text(note.updatedAt, format: .dateTime.month(.abbreviated).day().year())
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(min: 90, ideal: 100)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .onTableRowDoubleClick { open(rows[$0]) }
    }
    #else
    private var noteTable: some View {
        List(rows) { note in
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
