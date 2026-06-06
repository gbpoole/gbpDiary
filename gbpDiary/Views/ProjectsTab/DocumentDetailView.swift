import SwiftUI
import SwiftData
import QuickLook
import UniformTypeIdentifiers

struct DocumentDetailView: View {
    @Bindable var document: Document
    var asSheet: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var previewURL: URL?
    @State private var showingFilePicker = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        if asSheet {
            NavigationStack {
                coreContent
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 400)
            #endif
        } else {
            coreContent
        }
    }

    @ViewBuilder private var coreContent: some View {
        List {
            Section("Summary") {
                TextField("Summary", text: Binding(
                    get: { document.summary ?? "" },
                    set: { document.summary = $0.isEmpty ? nil : $0 }
                ))
            }

            Section("Description") {
                TextField("Description", text: Binding(
                    get: { document.documentDescription ?? "" },
                    set: { document.documentDescription = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                    .lineLimit(3...8)
            }

            Section("Attachments (\(document.attachments.count))") {
                ForEach(document.attachments.sorted { $0.createdAt < $1.createdAt }) { attachment in
                    AttachmentRow(attachment: attachment, onPreview: { previewURL = attachment.fileURL })
                }
                .onDelete { offsets in
                    let sorted = document.attachments.sorted { $0.createdAt < $1.createdAt }
                    for i in offsets {
                        AttachmentStorage.delete(at: sorted[i].fileURL)
                        modelContext.delete(sorted[i])
                    }
                }
                Button { showingFilePicker = true } label: {
                    Label("Add File", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Document")
        .toolbar {
            if asSheet {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete") { showingDeleteConfirm = true }
                        .foregroundStyle(.red)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .alert("Delete Document?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                for att in document.attachments { AttachmentStorage.delete(at: att.fileURL) }
                modelContext.delete(document)
                dismiss()
            }
        } message: {
            Text("This will permanently delete the document and all its attachments.")
        }
        .quickLookPreview($previewURL)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf, .image, .plainText, .json, .item],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let textExtensions: Set<String> = [
            "txt", "md", "markdown", "csv", "json", "yaml", "yml",
            "swift", "py", "js", "ts", "rb", "sh", "xml", "html", "htm"
        ]
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            let fileId = UUID()
            let copiedURL = try? AttachmentStorage.store(from: url, fileId: fileId)
            url.stopAccessingSecurityScopedResource()
            guard let copiedURL else { continue }

            let ext = url.pathExtension.lowercased()
            let kind: AttachmentKind
            if ext == "pdf" { kind = .pdf }
            else if ["png","jpg","jpeg","heic","gif","tiff","webp"].contains(ext) { kind = .image }
            else if textExtensions.contains(ext) { kind = .text }
            else { kind = .other }

            let att = Attachment(fileName: url.lastPathComponent, fileURL: copiedURL, kind: kind)
            att.fileSizeBytes = (try? copiedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            att.document = document
            modelContext.insert(att)
            document.attachments.append(att)
        }
        document.updatedAt = Date()
    }
}

private struct AttachmentRow: View {
    let attachment: Attachment
    let onPreview: () -> Void

    private var icon: String {
        switch attachment.kind {
        case .pdf:   "doc.richtext"
        case .image: "photo"
        case .text:  "doc.plaintext"
        case .other: "doc"
        }
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                if let size = attachment.fileSizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onPreview) {
                Image(systemName: "eye")
            }
            .buttonStyle(.plain)
        }
    }
}
