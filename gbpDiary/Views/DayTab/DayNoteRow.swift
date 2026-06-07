import SwiftUI
import SwiftData
import QuickLook
import UniformTypeIdentifiers

struct DayNoteRow: View {
    @Bindable var note: Note
    let focusedEntryId: FocusState<UUID?>.Binding
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var showingFilePicker = false
    @State private var previewURL: URL?

    private var isFocused: Bool { focusedEntryId.wrappedValue == note.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let project = note.project {
                    Chip(label: project.name, color: .blue)
                }
                ForEach(note.tags, id: \.self) { tag in
                    Chip(label: tag, color: .teal)
                }
                Spacer(minLength: 0)
                Button { showingFilePicker = true } label: {
                    Image(systemName: "paperclip")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                if let onEdit {
                    InlineRowEditButton(action: onEdit)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            EntryNotesSubArea(
                text: $note.content,
                isFocused: isFocused,
                focusedEntryId: focusedEntryId,
                focusId: note.id,
                placeholder: "Note…",
                onMoveToPrevious: onMoveToPrevious,
                onMoveToNext: onMoveToNext
            )

            if !note.attachments.isEmpty {
                attachmentStrip
            }
        }
        .padding(.horizontal)
        .contextMenu {
            Button("Edit…") { onEdit?() }
            #if os(macOS)
            if clipboardHasImage {
                Button("Paste Image from Clipboard") { pasteImageFromClipboard() }
            }
            #endif
            Divider()
            Button("Delete", role: .destructive) { onDelete?() }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.pdf, .image, .plainText, .json, .item],
            allowsMultipleSelection: true
        ) { handleImport($0) }
        .quickLookPreview($previewURL)
    }

    @ViewBuilder private var attachmentStrip: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(note.attachments.sorted { $0.createdAt < $1.createdAt }) { att in
                NoteAttachmentRow(
                    attachment: att,
                    onPreview: { previewURL = att.fileURL },
                    onDelete: {
                        removeMarkdownLink(for: att)
                        AttachmentStorage.delete(at: att.fileURL)
                        modelContext.delete(att)
                        note.attachments.removeAll { $0.id == att.id }
                    }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: - File import

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
            else if ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"].contains(ext) { kind = .image }
            else if textExtensions.contains(ext) { kind = .text }
            else { kind = .other }

            let att = Attachment(fileName: url.lastPathComponent, fileURL: copiedURL, kind: kind)
            att.fileSizeBytes = (try? copiedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            att.note = note
            modelContext.insert(att)
            note.attachments.append(att)
            if kind == .image { appendMarkdownLink(for: att) }
        }
        note.updatedAt = Date()
    }

    // MARK: - Clipboard paste

    #if os(macOS)
    private var clipboardHasImage: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    private func pasteImageFromClipboard() {
        let pb = NSPasteboard.general
        let pngData: Data?
        if let raw = pb.data(forType: .png) {
            pngData = raw
        } else if let tiff = pb.data(forType: .tiff),
                  let nsImage = NSImage(data: tiff),
                  let tiffRep = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffRep) {
            pngData = bitmapRep.representation(using: .png, properties: [:])
        } else {
            pngData = nil
        }
        guard let data = pngData else { return }

        let fileId = UUID()
        let dest = AttachmentStorage.attachmentsDirectory
            .appendingPathComponent(fileId.uuidString)
            .appendingPathExtension("png")
        guard (try? data.write(to: dest)) != nil else { return }

        let att = Attachment(fileName: "pasted_image.png", fileURL: dest, kind: .image)
        att.fileSizeBytes = data.count
        att.note = note
        modelContext.insert(att)
        note.attachments.append(att)
        appendMarkdownLink(for: att)
        note.updatedAt = Date()
    }
    #endif

    // MARK: - Markdown link helpers

    private func appendMarkdownLink(for att: Attachment) {
        let link = "![\(att.fileName)](\(att.fileURL.absoluteString))"
        note.content = note.content.isEmpty ? link : note.content + "\n" + link
    }

    private func removeMarkdownLink(for att: Attachment) {
        let link = "![\(att.fileName)](\(att.fileURL.absoluteString))"
        note.content = note.content
            .replacingOccurrences(of: "\n" + link, with: "")
            .replacingOccurrences(of: link + "\n", with: "")
            .replacingOccurrences(of: link, with: "")
    }
}

private struct NoteAttachmentRow: View {
    let attachment: Attachment
    let onPreview: () -> Void
    let onDelete: () -> Void

    private var icon: String {
        switch attachment.kind {
        case .pdf:   "doc.richtext"
        case .image: "photo"
        case .text:  "doc.plaintext"
        case .other: "doc"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(attachment.fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button(action: onPreview) {
                Image(systemName: "eye")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
    }
}
