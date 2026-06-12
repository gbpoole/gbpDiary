import SwiftUI
import SwiftData

struct DocumentsListView: View {
    @Query(sort: \Document.createdAt, order: .reverse) private var allDocuments: [Document]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedDocument: Document?
    @State private var creatingDocument: Document? = nil
    @State private var projectFilter: Project? = nil

    private var filteredDocuments: [Document] {
        guard let proj = projectFilter else { return allDocuments }
        return allDocuments.filter { $0.projects.contains(where: { $0.id == proj.id }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            documentTable
        }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem {
                Button {
                    let doc = Document()
                    modelContext.insert(doc)
                    creatingDocument = doc
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $selectedDocument) { DocumentDetailView(document: $0, asSheet: true) }
        .sheet(item: $creatingDocument) { DocumentDetailView(document: $0, asSheet: true) }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Project", selection: $projectFilter) {
                Text("Any Project").tag(Optional<Project>.none)
                ForEach(allProjects) { p in
                    Text(p.name).tag(Optional(p))
                }
            }
            .labelsHidden()
            .fixedSize()
            if projectFilter != nil {
                Button("Clear") { projectFilter = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    #if os(macOS)
    private var documentTable: some View {
        Table(filteredDocuments) {
            TableColumn("Summary") { document in
                Text(document.summary ?? "Untitled")
                    .lineLimit(1)
                    .onTapGesture { selectedDocument = document }
            }
            TableColumn("Description") { document in
                Text(document.documentDescription ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            TableColumn("Projects") { document in
                Text(document.projects.map(\.name).joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(160)
            TableColumn("Created") { document in
                Text(document.createdAt, format: .dateTime.month(.abbreviated).day().year())
                    .foregroundStyle(.secondary)
            }
            .width(100)
        }
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
                    if allProjects.isEmpty {
                        Text("No projects yet — add them in the Projects tab.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(allProjects) { p in
                            Toggle(p.name, isOn: Binding(
                                get: { selectedProjectIds.contains(p.id) },
                                set: { if $0 { selectedProjectIds.insert(p.id) } else { selectedProjectIds.remove(p.id) } }
                            ))
                        }
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
