import SwiftUI
import SwiftData

struct DocumentsListView: View {
    @Query(sort: \Document.createdAt, order: .reverse) private var allDocuments: [Document]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedDocument: Document?
    @State private var showingAdd = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedDocument) {
                ForEach(allDocuments) { doc in
                    DocumentRowView(document: doc).tag(doc)
                }
                .onDelete { offsets in
                    for i in offsets { modelContext.delete(allDocuments[i]) }
                }
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
        } detail: {
            if let doc = selectedDocument {
                DocumentDetailView(document: doc, asSheet: false)
            } else {
                ContentUnavailableView("Select a Document",
                                       systemImage: "doc",
                                       description: Text("Choose a document from the sidebar."))
            }
        }
        .sheet(isPresented: $showingAdd) {
            DocumentEditorSheet(document: nil)
        }
    }
}

private struct DocumentRowView: View {
    let document: Document
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.summary ?? "Untitled document")
                .font(.subheadline.bold())
            if let desc = document.documentDescription, !desc.isEmpty {
                Text(desc).foregroundStyle(.secondary).font(.callout).lineLimit(1)
            }
            HStack(spacing: 4) {
                Text(document.createdAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption).foregroundStyle(.tertiary)
                ForEach(document.projects) { p in
                    Chip(label: p.name, color: .blue)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct DocumentEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let document: Document?

    @Query(sort: \Project.name) private var allProjects: [Project]

    @State private var summary = ""
    @State private var docDescription = ""
    @State private var selectedProjectIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Document") {
                    TextField("Summary", text: $summary)
                    TextField("Description (optional)", text: $docDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Projects") {
                    ForEach(allProjects) { p in
                        Toggle(p.name, isOn: Binding(
                            get: { selectedProjectIds.contains(p.id) },
                            set: { if $0 { selectedProjectIds.insert(p.id) } else { selectedProjectIds.remove(p.id) } }
                        ))
                    }
                }
            }
            .navigationTitle(document == nil ? "New Document" : "Edit Document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(document == nil ? "Add" : "Save") { save() }
                }
            }
        }
        .onAppear {
            if let d = document {
                summary = d.summary ?? ""
                docDescription = d.documentDescription ?? ""
                selectedProjectIds = Set(d.projects.map(\.id))
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 320)
        #endif
    }

    private func save() {
        let linkedProjects = allProjects.filter { selectedProjectIds.contains($0.id) }
        if let d = document {
            d.summary = summary.isEmpty ? nil : summary
            d.documentDescription = docDescription.isEmpty ? nil : docDescription
            d.projects = linkedProjects
            d.updatedAt = Date()
        } else {
            let d = Document()
            d.summary = summary.isEmpty ? nil : summary
            d.documentDescription = docDescription.isEmpty ? nil : docDescription
            d.projects = linkedProjects
            modelContext.insert(d)
        }
        dismiss()
    }
}
