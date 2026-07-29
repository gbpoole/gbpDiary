import SwiftUI
import SwiftData

struct DocumentsListView: View {
    @Query(sort: \Document.createdAt, order: .reverse) private var allDocuments: [Document]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace

    @State private var activeFilterIds: Set<String> = []

    private var documentFilters: [PickerFilter<Document>] {
        allProjects.map { p in
            PickerFilter<Document>(id: "project.\(p.id)", label: p.name, chipColor: AppTheme.project, group: "Project") {
                $0.projects.contains(where: { $0.id == p.id })
            }
        }
    }

    private var filteredDocuments: [Document] {
        FilterEngine.apply(allDocuments, filters: documentFilters, activeIds: activeFilterIds)
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(
                filters: documentFilters,
                activeFilterIds: $activeFilterIds,
                onClearAll: { activeFilterIds = [] }
            )
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
    }

    #if os(macOS)
    private var documentTable: some View {
        Table(filteredDocuments) {
            TableColumn("Summary") { document in
                Text(document.summary ?? "Untitled")
                    .lineLimit(1)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.text)
                    .onTapGesture { workspace.focusOrOpen(.document(document.persistentModelID)) }
            }
            TableColumn("Description") { document in
                Text(document.documentDescription ?? "")
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
            TableColumn("Projects") { document in
                Text(document.projects.map(\.name).joined(separator: ", "))
                    .foregroundStyle(AppTheme.project)
                    .lineLimit(1)
            }
            .width(160)
            TableColumn("Created") { document in
                Text(document.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(100)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
    }
    #else
    private var documentTable: some View {
        List(filteredDocuments) { document in
            VStack(alignment: .leading, spacing: 4) {
                Text(document.summary ?? "Untitled")
                    .font(.subheadline.bold())
                if let desc = document.documentDescription, !desc.isEmpty {
                    Text(desc).foregroundStyle(.secondary).font(.callout).lineLimit(1)
                }
            }
            .onTapGesture { selectedDocument = document }
        }
    }
    #endif
}

struct DocumentEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceModel.self) private var workspace

    let document: Document?

    @Query(sort: \Project.name) private var allProjects: [Project]

    @State private var summary = ""
    @State private var docDescription = ""
    @State private var selectedProjects: [Project] = []
    @State private var showingDeleteConfirm = false

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
                }
                .padding()
            }
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
