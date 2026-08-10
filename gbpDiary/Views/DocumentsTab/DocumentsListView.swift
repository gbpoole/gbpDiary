import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DocumentsListView: View {
    @Query(sort: \Document.createdAt, order: .reverse) private var allDocuments: [Document]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace

    // @Model exposes `id: UUID` (its @Attribute), so the Table's selection is keyed by UUID.
    @State private var selection: Set<UUID> = []
    @State private var stashedSelection: Set<UUID> = []
    @State private var confirmingBulkDelete = false

    // Filter/search/sort live on the active tab (persisted + remembered across tab switches).
    private var filter: ListPageFilter { workspace.active.pageFilter(for: .documents) }
    private static let sortColumns: [SortColumn<Document>] = [
        SortColumn("summary", \.summaryKey), SortColumn("description", \.descriptionKey),
        SortColumn("projects", \.projectsKey), SortColumn("files", \.attachmentCount),
        SortColumn("created", \.createdAt),
    ]
    private var sortOrderBinding: Binding<[KeyPathComparator<Document>]> {
        let f = filter
        return Binding(
            get: { TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "created") },
            set: { if let d = TableSortPersistence.descriptor(for: $0, columns: Self.sortColumns) { f.sortColumnID = d.id; f.sortAscending = d.ascending } }
        )
    }

    private var documentFilters: [PickerFilter<Document>] {
        allProjects.map { p in
            PickerFilter<Document>(id: "project.\(p.id)", label: p.name, chipColor: AppTheme.project, group: "Project") {
                $0.projects.contains(where: { $0.id == p.id })
            }
        }
    }

    private var rows: [Document] {
        let f = filter
        let matched = FilterEngine.apply(allDocuments, filters: documentFilters, activeIds: f.activeFilterIds)
        let query = f.searchText.trimmingCharacters(in: .whitespaces)
        let searched = query.isEmpty ? matched : matched.filter { FuzzyMatch.matches(query, in: searchHaystack($0)) }
        return searched.sorted(using: TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "created"))
    }

    private func searchHaystack(_ d: Document) -> String {
        [d.summary, d.documentDescription, d.projects.map(\.name).joined(separator: " ")]
            .compactMap { $0 }.joined(separator: " ")
    }

    private var selectedDocuments: [Document] {
        allDocuments.filter { selection.contains($0.id) }
    }

    private func clearSelection() { selection.removeAll(); stashedSelection.removeAll() }

    private func bulkDelete() {
        for d in selectedDocuments {
            workspace.closeEntity(d.persistentModelID)
            modelContext.delete(d)
        }
        clearSelection()
    }

    var body: some View {
        @Bindable var f = filter
        return VStack(spacing: 0) {
            ListToolbar(
                searchText: $f.searchText,
                searchPrompt: "Search documents…",
                filters: documentFilters,
                activeFilterIds: $f.activeFilterIds,
                onClearAll: { f.activeFilterIds = [] }
            )
            BulkActionBar(count: selection.count, onClear: { clearSelection() }) {
                Button("Delete", role: .destructive) { confirmingBulkDelete = true }
            }
            Divider()
            documentTable
        }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem {
                Button {
                    let doc = Document()
                    modelContext.insert(doc)
                    workspace.focusOrOpen(.document(doc.persistentModelID))
                } label: { Image(systemName: "plus") }
            }
        }
        .alert("Delete \(selection.count) document\(selection.count == 1 ? "" : "s")?", isPresented: $confirmingBulkDelete) {
            Button("Delete", role: .destructive) { bulkDelete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently deletes the selected document\(selection.count == 1 ? "" : "s") and their attachments.") }
        .onChange(of: Set(rows.map(\.id))) { _, visible in
            let result = TableSelectionReconcile.reconcile(selection: selection, stashed: stashedSelection, visible: visible)
            if result.selection != selection { selection = result.selection }
            if result.stashed != stashedSelection { stashedSelection = result.stashed }
        }
    }

    private func open(_ document: Document) { workspace.focusOrOpen(.document(document.persistentModelID)) }

    #if os(macOS)
    private var documentTable: some View {
        Table(rows, selection: $selection, sortOrder: sortOrderBinding) {
            TableColumn("Summary", value: \.summaryKey) { document in
                Text(document.summary ?? "Untitled")
                    .lineLimit(1)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.text)
            }
            .width(min: 140, ideal: 220)
            TableColumn("Description", value: \.descriptionKey) { document in
                Text(document.documentDescription ?? "")
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 220)
            TableColumn("Projects", value: \.projectsKey) { document in
                Text(document.projects.map(\.name).joined(separator: ", "))
                    .foregroundStyle(AppTheme.project)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 160)
            TableColumn("Files", value: \.attachmentCount) { document in
                Text("\(document.attachmentCount)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(min: 50, ideal: 60)
            TableColumn("Created", value: \.createdAt) { document in
                Text(document.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(min: 90, ideal: 100)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .onTableRowDoubleClick { open(rows[$0]) }
    }
    #else
    private var documentTable: some View {
        List(rows) { document in
            VStack(alignment: .leading, spacing: 4) {
                Text(document.summary ?? "Untitled")
                    .font(.subheadline.bold())
                if let desc = document.documentDescription, !desc.isEmpty {
                    Text(desc).foregroundStyle(.secondary).font(.callout).lineLimit(1)
                }
            }
            .onTapGesture { open(document) }
        }
    }
    #endif
}

struct DocumentEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceModel.self) private var workspace

    let document: Document?
    /// When true, at least one attached file is required before the document can be saved.
    var requireAttachment: Bool = false

    @Query(sort: \Project.name) private var allProjects: [Project]

    @State private var summary = ""
    @State private var docDescription = ""
    @State private var selectedProjects: [Project] = []
    @State private var showingDeleteConfirm = false
    @State private var showingFilePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Summary") {
                        TextField("Summary", text: $summary)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    }
                    GroupBox("Description") {
                        TextField("Description (optional)", text: $docDescription, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    }
                    GroupBox("Projects") {
                        FuzzyPickerField(
                            allItems: allProjects,
                            selected: $selectedProjects,
                            label: \.name,
                            chipColor: AppTheme.project,
                            onCreateItem: { makeProject($0) },
                            tapArea: true,
                            emptyLabel: "None — tap to link projects"
                        )
                    }
                    if let d = document { filesSection(d) }
                }
                .padding()
            }
            .fileImporter(isPresented: $showingFilePicker,
                          allowedContentTypes: [.pdf, .image, .plainText, .json, .item],
                          allowsMultipleSelection: true) { handleImport($0) }
            .navigationTitle(document == nil ? "New Document" : "Edit Document")
            .toolbar {
                if document != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete") { showingDeleteConfirm = true }
                            .buttonStyle(.borderedProminent).tint(.red)
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(document == nil ? "Add" : "Save") { save() }
                        .disabled(requireAttachment && (document?.attachments.isEmpty ?? true))
                }
            }
            .alert("Delete Document?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteDocument() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the document and its attachments.")
            }
        }
        .onAppear {
            if let d = document {
                summary = d.summary ?? ""
                docDescription = d.documentDescription ?? ""
                selectedProjects = d.projects
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    private func filesSection(_ d: Document) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if d.attachments.isEmpty {
                    Text("No files yet — add at least one.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(d.attachments) { att in
                        HStack(spacing: 6) {
                            Image(systemName: icon(for: att.kind)).foregroundStyle(.secondary).font(.system(size: 13))
                            Text(att.fileName).lineLimit(1)
                            Spacer(minLength: 0)
                            Button { removeAttachment(att, from: d) } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button("Add file…") { showingFilePicker = true }
                    .font(.callout).foregroundStyle(AppTheme.accent).buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(requireAttachment ? "Files (required)" : "Files")
        }
    }

    private func icon(for kind: AttachmentKind) -> String {
        switch kind {
        case .pdf:   "doc.richtext"
        case .image: "photo"
        case .text:  "doc.text"
        case .other: "doc"
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let d = document else { return }
        let textExtensions: Set<String> = [
            "txt","md","markdown","csv","json","yaml","yml","swift","py","js","ts","rb","sh","xml","html","htm"
        ]
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            let fileId = UUID()
            let copied = try? AttachmentStorage.store(from: url, fileId: fileId)
            url.stopAccessingSecurityScopedResource()
            guard let copied else { continue }
            let ext = url.pathExtension.lowercased()
            let kind: AttachmentKind = ext == "pdf" ? .pdf
                : ["png","jpg","jpeg","heic","gif","tiff","webp"].contains(ext) ? .image
                : textExtensions.contains(ext) ? .text : .other
            let att = Attachment(fileName: url.lastPathComponent, fileURL: copied, kind: kind)
            att.fileSizeBytes = (try? copied.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
            att.document = d
            modelContext.insert(att)
            d.attachments.append(att)
        }
        d.updatedAt = Date()
    }

    private func removeAttachment(_ att: Attachment, from d: Document) {
        AttachmentStorage.delete(at: att.fileURL)
        modelContext.delete(att)
        d.updatedAt = Date()
    }

    // Create a new Project on the fly while linking one (auto-added to the selection).
    private func makeProject(_ projectName: String) -> Project? {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let project = Project(name: trimmed)
        modelContext.insert(project)
        return project
    }

    private func save() {
        if let d = document {
            d.summary = summary.isEmpty ? nil : summary
            d.documentDescription = docDescription.isEmpty ? nil : docDescription
            d.projects = selectedProjects
            d.updatedAt = Date()
        } else {
            let d = Document()
            d.summary = summary.isEmpty ? nil : summary
            d.documentDescription = docDescription.isEmpty ? nil : docDescription
            d.projects = selectedProjects
            modelContext.insert(d)
        }
        dismiss()
    }

    private func deleteDocument() {
        guard let d = document else { return }
        workspace.closeEntity(d.persistentModelID)
        modelContext.delete(d)
        dismiss()
    }
}
