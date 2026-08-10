import SwiftUI
import SwiftData

struct MinutesListView: View {
    @Query(sort: \Minutes.meetingAt, order: .reverse) private var allMinutes: [Minutes]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace

    @State private var editingMinutes: Minutes?
    @State private var showingAdd = false
    // @Model exposes `id: UUID` (its @Attribute), so the Table's selection is keyed by UUID.
    @State private var selection: Set<UUID> = []
    @State private var stashedSelection: Set<UUID> = []
    @State private var confirmingBulkDelete = false

    // Filter/search/sort live on the active tab (persisted + remembered across tab switches).
    // The Date and Time columns both sort by `meetingAt`, so they share the "date" id.
    private var filter: ListPageFilter { workspace.active.pageFilter(for: .meetings) }
    private static let sortColumns: [SortColumn<Minutes>] = [
        SortColumn("date", \.meetingAt), SortColumn("summary", \.summaryKey),
        SortColumn("projects", \.projectsKey), SortColumn("attendees", \.attendeeCount),
    ]
    private var sortOrderBinding: Binding<[KeyPathComparator<Minutes>]> {
        let f = filter
        return Binding(
            get: { TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "date") },
            set: { if let d = TableSortPersistence.descriptor(for: $0, columns: Self.sortColumns) { f.sortColumnID = d.id; f.sortAscending = d.ascending } }
        )
    }

    private var minutesFilters: [PickerFilter<Minutes>] {
        let projectGroup = allProjects.map { p in
            PickerFilter<Minutes>(id: "project.\(p.id)", label: p.name, chipColor: AppTheme.project, group: "Project") {
                $0.projects.contains(where: { $0.id == p.id })
            }
        }
        let attendeeGroup = allPeople.map { person in
            PickerFilter<Minutes>(id: "attendee.\(person.id)", label: person.name, chipColor: AppTheme.person, group: "Attendee") {
                $0.attendees.contains(where: { $0.id == person.id })
            }
        }
        return projectGroup + attendeeGroup
    }

    private var rows: [Minutes] {
        let f = filter
        let matched = FilterEngine.apply(allMinutes, filters: minutesFilters, activeIds: f.activeFilterIds)
        let query = f.searchText.trimmingCharacters(in: .whitespaces)
        let searched = query.isEmpty ? matched : matched.filter { FuzzyMatch.matches(query, in: searchHaystack($0)) }
        return searched.sorted(using: TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "date"))
    }

    private func searchHaystack(_ m: Minutes) -> String {
        [m.summary, m.projects.map(\.name).joined(separator: " "), m.attendees.map(\.name).joined(separator: " ")]
            .compactMap { $0 }.joined(separator: " ")
    }

    private var selectedMinutes: [Minutes] {
        allMinutes.filter { selection.contains($0.id) }
    }

    private func clearSelection() { selection.removeAll(); stashedSelection.removeAll() }

    private func bulkDelete() {
        for m in selectedMinutes {
            workspace.closeEntity(m.persistentModelID)
            modelContext.delete(m)
        }
        clearSelection()
    }

    var body: some View {
        @Bindable var f = filter
        return VStack(spacing: 0) {
            ListToolbar(
                searchText: $f.searchText,
                searchPrompt: "Search minutes…",
                filters: minutesFilters,
                activeFilterIds: $f.activeFilterIds,
                onClearAll: { f.activeFilterIds = [] }
            )
            BulkActionBar(count: selection.count, onClear: { clearSelection() }) {
                Button("Delete", role: .destructive) { confirmingBulkDelete = true }
            }
            Divider()
            minutesTable
        }
        .navigationTitle("Minutes")
        .toolbar {
            ToolbarItem {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editingMinutes) { MinutesDetailView(minutes: $0, asSheet: true) }
        .sheet(isPresented: $showingAdd) { MinutesEditorSheet(minutes: nil, project: nil) }
        .alert("Delete \(selection.count) meeting\(selection.count == 1 ? "" : "s")?", isPresented: $confirmingBulkDelete) {
            Button("Delete", role: .destructive) { bulkDelete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes the selected meeting\(selection.count == 1 ? "" : "s") and their minutes. Related items are unlinked, not deleted.") }
        .onChange(of: Set(rows.map(\.id))) { _, visible in
            let result = TableSelectionReconcile.reconcile(selection: selection, stashed: stashedSelection, visible: visible)
            if result.selection != selection { selection = result.selection }
            if result.stashed != stashedSelection { stashedSelection = result.stashed }
        }
    }

    private func openInspector(for minutes: Minutes) {
        workspace.openInNewTab(.minutes(minutes.persistentModelID))
    }

    #if os(macOS)
    private var minutesTable: some View {
        Table(rows, selection: $selection, sortOrder: sortOrderBinding) {
            TableColumn("Date", value: \.meetingAt) { minutes in
                Text(minutes.meetingAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                    .lineLimit(1)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.text)
                    .contextMenu { editMenuItem(minutes) }
            }
            .width(min: 130, ideal: 160)
            TableColumn("Time", value: \.meetingAt) { minutes in
                Text(minutes.meetingAt, format: .dateTime.hour().minute())
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(min: 60, ideal: 70)
            TableColumn("Summary", value: \.summaryKey) { minutes in
                Text(minutes.summary ?? "")
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)
                    .contextMenu { editMenuItem(minutes) }
            }
            .width(min: 160, ideal: 260)
            TableColumn("Projects", value: \.projectsKey) { minutes in
                Text(minutes.projects.map(\.name).joined(separator: ", "))
                    .foregroundStyle(AppTheme.project)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 160)
            TableColumn("Attendees", value: \.attendeeCount) { minutes in
                Text("\(minutes.attendeeCount)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(min: 70, ideal: 80)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .onTableRowDoubleClick { openInspector(for: rows[$0]) }
    }
    #else
    private var minutesTable: some View {
        List(rows) { minutes in
            VStack(alignment: .leading, spacing: 4) {
                Text(minutes.meetingAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                    .font(.subheadline.bold())
                if let s = minutes.summary, !s.isEmpty {
                    Text(s).foregroundStyle(.secondary).font(.callout).lineLimit(1)
                }
            }
            .onTapGesture { openInspector(for: minutes) }
            .contextMenu { editMenuItem(minutes) }
        }
    }
    #endif

    @ViewBuilder
    private func editMenuItem(_ minutes: Minutes) -> some View {
        Button("Edit meeting info…") { editingMinutes = minutes }
    }
}
