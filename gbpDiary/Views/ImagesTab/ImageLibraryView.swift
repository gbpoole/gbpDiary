import SwiftUI
import SwiftData

// Browse and manage image attachments. Shows each image's display name, description, size, and
// where it is used (which notes reference its attachment:// id). Images referenced by no note and
// not attached to a document are "unused" and can be cleaned up.
struct ImageLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace
    @Query private var allAttachments: [Attachment]
    @Query private var allNotes: [Note]

    @State private var selected: Attachment?
    @State private var showingDeleteUnused = false

    // Search/sort live on the active tab (persisted + remembered across tab switches). Images have no
    // discrete filter dimension — the toolbar collapses to search-only (Light tier).
    private var filter: ListPageFilter { workspace.active.pageFilter(for: .images) }
    private static let sortColumns: [SortColumn<Attachment>] = [
        SortColumn("name", \.nameKey), SortColumn("description", \.descriptionKey),
        SortColumn("size", \.sizeSortKey),
    ]
    private var sortOrderBinding: Binding<[KeyPathComparator<Attachment>]> {
        let f = filter
        return Binding(
            get: { TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "name") },
            set: { if let d = TableSortPersistence.descriptor(for: $0, columns: Self.sortColumns) { f.sortColumnID = d.id; f.sortAscending = d.ascending } }
        )
    }

    // All image attachments (unsorted/unsearched) — drives the header counts and Delete Unused.
    private var images: [Attachment] {
        allAttachments.filter { $0.kind == .image }
    }

    // The searched + sorted rows shown in the table.
    private var rows: [Attachment] {
        let f = filter
        let query = f.searchText.trimmingCharacters(in: .whitespaces)
        let searched = query.isEmpty ? images
            : images.filter { FuzzyMatch.matches(query, in: searchHaystack($0)) }
        return searched.sorted(using: TableSortPersistence.order(id: f.sortColumnID, ascending: f.sortAscending, columns: Self.sortColumns, fallbackID: "name"))
    }

    private func searchHaystack(_ att: Attachment) -> String {
        [att.libraryName, att.attachmentDescription].compactMap { $0 }.joined(separator: " ")
    }

    // Attachment id → the notes that reference it in markdown.
    private var usageByID: [UUID: [Note]] {
        var map: [UUID: [Note]] = [:]
        for note in allNotes {
            for id in Set(AttachmentRef.referencedIDs(in: note.content)) {
                map[id, default: []].append(note)
            }
        }
        return map
    }

    private func isUnused(_ att: Attachment) -> Bool {
        att.document == nil && (usageByID[att.id]?.isEmpty ?? true)
    }

    private var unusedImages: [Attachment] { images.filter(isUnused) }

    var body: some View {
        @Bindable var f = filter
        return VStack(spacing: 0) {
            ListToolbar<Attachment>(
                searchText: $f.searchText,
                searchPrompt: "Search images…",
                activeFilterIds: $f.activeFilterIds
            )
            header
            Divider()
            if images.isEmpty {
                ContentUnavailableView("No images", systemImage: "photo.on.rectangle",
                                       description: Text("Images added to notes appear here."))
            } else {
                imageTable
            }
        }
        .sheet(item: $selected) { att in
            ImageDetailSheet(attachment: att, usage: usageByID[att.id] ?? [], noteTitle: noteTitle)
        }
        .alert("Delete Unused Images?", isPresented: $showingDeleteUnused) {
            Button("Delete \(unusedImages.count)", role: .destructive) { deleteUnused() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes \(unusedImages.count) image file(s) referenced by no note.")
        }
    }

    private var header: some View {
        HStack {
            Text("\(images.count) image\(images.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            if !unusedImages.isEmpty {
                Text("· \(unusedImages.count) unused")
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("Delete Unused") { showingDeleteUnused = true }
                .disabled(unusedImages.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    #if os(macOS)
    private var imageTable: some View {
        // "Used in" derives from a cross-note markdown scan (not a model keypath) and the thumbnail /
        // trash columns have no value, so those three are not header-sortable; the rest are.
        Table(rows, sortOrder: sortOrderBinding) {
            TableColumn("") { att in
                ImageThumbnail(url: att.fileURL, size: 40)
            }
            .width(52)
            TableColumn("Name", value: \.nameKey) { att in
                Text(att.libraryName)
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 220)
            TableColumn("Description", value: \.descriptionKey) { att in
                Text(att.attachmentDescription ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 220)
            TableColumn("Used in") { att in
                usageLabel(att)
            }
            .width(min: 120, ideal: 160)
            TableColumn("Size", value: \.sizeSortKey) { att in
                Text(sizeText(att)).foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 80)
            TableColumn("") { att in
                Button { deleteImage(att) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(!isUnused(att))
                .foregroundStyle(isUnused(att) ? Color.red : Color.secondary.opacity(0.4))
                .help(isUnused(att) ? "Delete image" : "In use — remove references first")
            }
            .width(36)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .onTableRowDoubleClick { selected = rows[$0] }
    }
    #else
    private var imageTable: some View {
        List(rows) { att in
            HStack(spacing: 10) {
                ImageThumbnail(url: att.fileURL, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(att.displayName ?? att.fileName).lineLimit(1)
                    usageLabel(att)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selected = att }
        }
    }
    #endif

    @ViewBuilder
    private func usageLabel(_ att: Attachment) -> some View {
        if att.document != nil {
            Text("Document").foregroundStyle(.secondary).font(.caption)
        } else if let notes = usageByID[att.id], !notes.isEmpty {
            Text(notes.count == 1 ? noteTitle(notes[0]) : "\(notes.count) notes")
                .foregroundStyle(.secondary).font(.caption).lineLimit(1)
        } else {
            Text("Unused").foregroundStyle(.orange).font(.caption)
        }
    }

    private func deleteImage(_ att: Attachment) {
        AttachmentStorage.delete(at: att.fileURL)
        modelContext.delete(att)
    }

    private func sizeText(_ att: Attachment) -> String {
        guard let bytes = att.fileSizeBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func noteTitle(_ note: Note) -> String {
        if let date = note.dayRecord?.date {
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
        if let m = note.minutes { return m.summary ?? "Meeting" }
        if let p = note.project { return p.name }
        let firstLine = note.content.split(separator: "\n").first.map(String.init) ?? ""
        return firstLine.isEmpty ? "Note" : String(firstLine.prefix(30))
    }

    private func deleteUnused() {
        for att in unusedImages {
            AttachmentStorage.delete(at: att.fileURL)
            modelContext.delete(att)
        }
    }
}

// MARK: - Thumbnail

struct ImageThumbnail: View {
    let url: URL
    var size: CGFloat = 40

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                Image(systemName: "photo").foregroundStyle(.secondary)
            default:
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.1)))
    }
}

// MARK: - Detail / edit sheet

struct ImageDetailSheet: View {
    @Bindable var attachment: Attachment
    let usage: [Note]
    let noteTitle: (Note) -> String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceModel.self) private var workspace
    @State private var showingDelete = false

    private var isUsed: Bool { attachment.document != nil || !usage.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ImageThumbnail(url: attachment.fileURL, size: 200)
                        .frame(maxWidth: .infinity)

                    labeledField("Display name") {
                        TextField("Display name", text: Binding(
                            get: { attachment.displayName ?? "" },
                            set: { attachment.displayName = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    labeledField("Description") {
                        TextField("What this image shows…", text: Binding(
                            get: { attachment.attachmentDescription ?? "" },
                            set: { attachment.attachmentDescription = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                    }

                    labeledField("Used in") {
                        if attachment.document != nil {
                            Text("A document").foregroundStyle(.secondary)
                        } else if usage.isEmpty {
                            Text("Not referenced by any note").foregroundStyle(.orange)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(usage) { note in
                                    Button { reveal(note) } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.up.forward.square")
                                            Text(noteTitle(note))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(attachment.displayName ?? attachment.fileName)
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) { showingDelete = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Delete Image?", isPresented: $showingDelete) {
                Button("Delete", role: .destructive) { deleteImage() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(isUsed
                     ? "This image is still referenced. Deleting it will leave broken image links."
                     : "This permanently removes the image file.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        #endif
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func reveal(_ note: Note) {
        workspace.reveal(note: note)
        dismiss()
    }

    private func deleteImage() {
        AttachmentStorage.delete(at: attachment.fileURL)
        modelContext.delete(attachment)
        dismiss()
    }
}
