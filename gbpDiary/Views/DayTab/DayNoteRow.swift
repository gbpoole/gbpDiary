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
                    onPreview: { previewURL = att.renderURL ?? att.fileURL },
                    onDelete: {
                        removeMarkdownLink(for: att)
                        if let r = att.renderURL { AttachmentStorage.delete(at: r) }
                        AttachmentStorage.delete(at: att.fileURL)
                        modelContext.delete(att)
                        note.attachments.removeAll { $0.id == att.id }
                    },
                    onStepDown: att.kind == .image ? { stepRenderSize(for: att, by: -1) } : nil,
                    onStepUp:   att.kind == .image ? { stepRenderSize(for: att, by: +1) } : nil
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

            if kind == .image {
                setupRender(for: att, sourceURL: copiedURL)
                appendMarkdownLink(for: att)
            }
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
        setupRender(for: att, sourceURL: dest)
        appendMarkdownLink(for: att)
        note.updatedAt = Date()
    }
    #endif

    // MARK: - Image render setup

    private func setupRender(for att: Attachment, sourceURL: URL) {
        let srcWidth = AttachmentStorage.capSource(at: sourceURL)
        att.sourceImageWidth = srcWidth > 0 ? srcWidth : nil
        guard srcWidth > 0 else { return }
        let steps = AttachmentStorage.renderSteps(forSourceWidth: srcWidth)
        let initialWidth = steps.last(where: { $0 <= 800 }) ?? steps[0]
        guard let renderData = AttachmentStorage.resizedImageData(at: sourceURL, targetWidth: initialWidth) else { return }
        let renderURL = AttachmentStorage.renderURL(forSourceURL: sourceURL, width: initialWidth)
        try? renderData.write(to: renderURL)
        att.renderURL = renderURL
        att.renderWidth = initialWidth
    }

    private func stepRenderSize(for att: Attachment, by delta: Int) {
        guard att.kind == .image,
              let srcWidth = att.sourceImageWidth,
              let currentWidth = att.renderWidth else { return }
        let steps = AttachmentStorage.renderSteps(forSourceWidth: srcWidth)
        guard let idx = steps.firstIndex(of: currentWidth) else { return }
        let newIdx = idx + delta
        guard steps.indices.contains(newIdx) else { return }
        let newWidth = steps[newIdx]
        guard let data = AttachmentStorage.resizedImageData(at: att.fileURL, targetWidth: newWidth) else { return }
        let newRenderURL = AttachmentStorage.renderURL(forSourceURL: att.fileURL, width: newWidth)
        try? data.write(to: newRenderURL)
        if let oldRenderURL = att.renderURL {
            removeMarkdownLink(forURL: oldRenderURL, fileName: att.fileName)
            AttachmentStorage.delete(at: oldRenderURL)
        }
        att.renderURL = newRenderURL
        att.renderWidth = newWidth
        appendMarkdownLink(for: att)
        note.updatedAt = Date()
    }

    // MARK: - Markdown link helpers

    private func appendMarkdownLink(for att: Attachment) {
        let url = att.renderURL ?? att.fileURL
        let link = "![\(att.fileName)](\(url.absoluteString))"
        note.content = note.content.isEmpty ? link : note.content + "\n" + link
    }

    private func removeMarkdownLink(forURL url: URL, fileName: String) {
        let link = "![\(fileName)](\(url.absoluteString))"
        note.content = note.content
            .replacingOccurrences(of: "\n" + link, with: "")
            .replacingOccurrences(of: link + "\n", with: "")
            .replacingOccurrences(of: link, with: "")
    }

    private func removeMarkdownLink(for att: Attachment) {
        removeMarkdownLink(forURL: att.renderURL ?? att.fileURL, fileName: att.fileName)
    }
}

private struct NoteAttachmentRow: View {
    let attachment: Attachment
    let onPreview: () -> Void
    let onDelete: () -> Void
    var onStepDown: (() -> Void)? = nil
    var onStepUp: (() -> Void)? = nil

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
            if attachment.kind == .image,
               let srcWidth = attachment.sourceImageWidth,
               let currentWidth = attachment.renderWidth {
                let steps = AttachmentStorage.renderSteps(forSourceWidth: srcWidth)
                let atMin = steps.first == currentWidth
                let atMax = steps.last == currentWidth
                Text("\(currentWidth)px")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button { onStepDown?() } label: {
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(atMin ? Color.secondary.opacity(0.3) : .secondary)
                .disabled(atMin)
                Button { onStepUp?() } label: {
                    Image(systemName: "chevron.up").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(atMax ? Color.secondary.opacity(0.3) : .secondary)
                .disabled(atMax)
            }
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
