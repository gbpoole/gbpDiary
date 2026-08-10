import SwiftUI
import SwiftData

struct InstitutionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace
    @Query(sort: \Institution.name) private var institutions: [Institution]

    @State private var selectedInstitution: Institution?
    @State private var showingAddInstitution = false
    // @Model exposes `id: UUID` (its @Attribute), so the Table's selection is keyed by UUID.
    @State private var selection: Set<UUID> = []
    @State private var stashedSelection: Set<UUID> = []
    @State private var confirmingBulkDelete = false

    // Search/sort live on the active tab (persisted + remembered across tab switches). Institutions
    // have no discrete filter dimension — the toolbar collapses to search-only (Light tier).
    private var filter: ListPageFilter { workspace.active.pageFilter(for: .institutions) }
    private static let sortColumns: [SortColumn<Institution>] = [
        SortColumn("name", \.nameKey), SortColumn("members", \.memberCount),
        SortColumn("projects", \.projectCount),
    ]
    private var sortOrderBinding: Binding<[KeyPathComparator<Institution>]> {
        let f = filter
        return Binding(
            get: { TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "name") },
            set: { if let d = TableSortPersistence.descriptor(for: $0, columns: Self.sortColumns) { f.sortColumnID = d.id; f.sortAscending = d.ascending } }
        )
    }

    private var rows: [Institution] {
        let f = filter
        let query = f.searchText.trimmingCharacters(in: .whitespaces)
        let searched = query.isEmpty ? institutions : institutions.filter { FuzzyMatch.matches(query, in: $0.name) }
        return searched.sorted(using: TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "name"))
    }

    private var selectedInstitutions: [Institution] {
        institutions.filter { selection.contains($0.id) }
    }

    private func clearSelection() { selection.removeAll(); stashedSelection.removeAll() }

    private func bulkDelete() {
        for inst in selectedInstitutions {
            workspace.closeEntity(inst.persistentModelID)
            modelContext.delete(inst)
        }
        clearSelection()
    }

    var body: some View {
        @Bindable var f = filter
        return VStack(spacing: 0) {
            ListToolbar<Institution>(
                searchText: $f.searchText,
                searchPrompt: "Search institutions…",
                activeFilterIds: $f.activeFilterIds
            )
            BulkActionBar(count: selection.count, onClear: { clearSelection() }) {
                Button("Delete", role: .destructive) { confirmingBulkDelete = true }
            }
            Divider()
            institutionTable
        }
        .navigationTitle("Institutions")
        .toolbar {
            ToolbarItem {
                Button { showingAddInstitution = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $selectedInstitution) { InstitutionEditorSheet(institution: $0) }
        .sheet(isPresented: $showingAddInstitution) { InstitutionEditorSheet(institution: nil) }
        .alert("Delete \(selection.count) institution\(selection.count == 1 ? "" : "s")?", isPresented: $confirmingBulkDelete) {
            Button("Delete", role: .destructive) { bulkDelete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes the selected institution\(selection.count == 1 ? "" : "s"). Members and projects are unlinked, not deleted.") }
        .onChange(of: Set(rows.map(\.id))) { _, visible in
            let result = TableSelectionReconcile.reconcile(selection: selection, stashed: stashedSelection, visible: visible)
            if result.selection != selection { selection = result.selection }
            if result.stashed != stashedSelection { stashedSelection = result.stashed }
        }
    }

    // Row-tap rule: Institution is a light entity — open its editor sheet directly.
    private func open(_ institution: Institution) { selectedInstitution = institution }

    #if os(macOS)
    private var institutionTable: some View {
        Table(rows, selection: $selection, sortOrder: sortOrderBinding) {
            TableColumn("Name", value: \.nameKey) { institution in
                Text(institution.name)
                    .lineLimit(1)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.text)
            }
            .width(min: 160, ideal: 280)
            TableColumn("Members", value: \.memberCount) { institution in
                Text("\(institution.memberCount)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(min: 70, ideal: 80)
            TableColumn("Projects", value: \.projectCount) { institution in
                Text("\(institution.projectCount)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(min: 70, ideal: 80)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .onTableRowDoubleClick { open(rows[$0]) }
    }
    #else
    private var institutionTable: some View {
        List(rows) { institution in
            Text(institution.name)
                .onTapGesture { open(institution) }
        }
    }
    #endif
}

struct InstitutionEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceModel.self) private var workspace

    let institution: Institution?
    @State private var name = ""
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Name") {
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                    }
                    if let inst = institution {
                        GroupBox("Members (\(inst.members.count))") {
                            membersList(inst)
                        }
                        GroupBox("Projects (\(inst.projects.count))") {
                            projectsList(inst)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(institution == nil ? "New Institution" : "Edit Institution")
            .toolbar {
                if institution != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete") { showingDeleteConfirm = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(institution == nil ? "Add" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Delete Institution?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteInstitution() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the institution. Its members and projects are kept but no longer reference it.")
            }
        }
        .onAppear { name = institution?.name ?? "" }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    @ViewBuilder private func membersList(_ inst: Institution) -> some View {
        if inst.members.isEmpty {
            Text("No members.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(inst.members.sorted { $0.name < $1.name }) { person in
                    HStack {
                        Text(person.name)
                        if let email = person.primaryEmail {
                            Spacer()
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func projectsList(_ inst: Institution) -> some View {
        if inst.projects.isEmpty {
            Text("No linked projects.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(inst.projects.sorted { $0.name < $1.name }) { p in
                    Text(p.name)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let inst = institution {
            inst.name = trimmed
            inst.updatedAt = Date()
        } else {
            modelContext.insert(Institution(name: trimmed))
        }
        dismiss()
    }

    private func deleteInstitution() {
        guard let inst = institution else { return }
        workspace.closeEntity(inst.persistentModelID)
        modelContext.delete(inst)
        dismiss()
    }
}
