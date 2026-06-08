import SwiftUI
import SwiftData
import QuickLook
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct DayNoteRow: View {
    @Bindable var note: Note
    let focusedEntryId: FocusState<UUID?>.Binding
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onHeaderButtonTap: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var showingFilePicker = false
    @State private var previewURL: URL?
    @State private var blocksDropTargetIndex: Int?

    // True when any block within this note is focused
    private var isFocused: Bool {
        guard let id = focusedEntryId.wrappedValue else { return false }
        return note.blocks.contains { $0.id == id }
    }

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
                Button {
                    onHeaderButtonTap?()
                    showingFilePicker = true
                } label: {
                    Image(systemName: "paperclip")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                #if os(macOS)
                Button {
                    onHeaderButtonTap?()
                    pasteImageFromClipboard()
                } label: {
                    Image(systemName: "clipboard")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Button {
                    onHeaderButtonTap?()
                    exportAsPDF()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                #endif
                if let onEdit {
                    InlineRowEditButton(action: {
                        onHeaderButtonTap?()
                        onEdit()
                    })
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            blocksView

            // Non-image attachments (PDF, text, other) stay in the strip
            let nonImageAtts = note.attachments
                .filter { $0.kind != .image }
                .sorted { $0.createdAt < $1.createdAt }
            if !nonImageAtts.isEmpty {
                nonImageAttachmentStrip(nonImageAtts)
            }
        }
        .padding(.horizontal)
        .contextMenu {
            Button("Edit…") { onEdit?() }
            #if os(macOS)
            Button("Paste Image from Clipboard") { pasteImageFromClipboard() }
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

    // MARK: - Blocks

    @ViewBuilder private var blocksView: some View {
        let blocks = note.blocks
        VStack(spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                singleBlockView(block: block, index: index, in: blocks)
                    .draggable(block.id.uuidString)
                    // Overlay two half-height drop zones (top = insert before, bottom = insert after).
                    // Overlays don't affect layout, so no gaps are introduced.
                    .overlay {
                        VStack(spacing: 0) {
                            Color.clear
                                .dropDestination(for: String.self) { items, _ in
                                    guard let s = items.first else { return false }
                                    reorderBlock(draggedIdString: s, belowIndex: index - 1)
                                    return true
                                } isTargeted: { targeted in
                                    blocksDropTargetIndex = targeted ? (index - 1) : nil
                                }
                            Color.clear
                                .dropDestination(for: String.self) { items, _ in
                                    guard let s = items.first else { return false }
                                    reorderBlock(draggedIdString: s, belowIndex: index)
                                    return true
                                } isTargeted: { targeted in
                                    blocksDropTargetIndex = targeted ? index : nil
                                }
                        }
                    }
                    .overlay(alignment: .top) {
                        if blocksDropTargetIndex == index - 1 {
                            Color.accentColor.frame(height: 2)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if blocksDropTargetIndex == index {
                            Color.accentColor.frame(height: 2)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func singleBlockView(block: NoteBlock, index: Int, in blocks: [NoteBlock]) -> some View {
        let isFirst = index == 0
        let isLast  = index == blocks.count - 1
        switch block.kind {
        case .text:
            EntryNotesSubArea(
                text: textBinding(for: index),
                isFocused: focusedEntryId.wrappedValue == block.id,
                focusedEntryId: focusedEntryId,
                focusId: block.id,
                placeholder: "Note…",
                onMoveToPrevious: moveToPreviousAction(from: index, in: blocks),
                onMoveToNext: moveToNextAction(from: index, in: blocks),
                topRounded: isFirst,
                bottomRounded: isLast
            )
        case .image:
            let attId = block.attachmentId
            let att = note.attachments.first { $0.id == attId }
            if let att {
                NoteImageBlockRow(
                    note: note,
                    block: block,
                    blockIndex: index,
                    att: att,
                    onPreview: { previewURL = att.renderURL ?? att.fileURL },
                    onDelete: { deleteImageBlock(at: index, att: att) },
                    onStepDown: { stepRenderSize(for: att, by: -1) },
                    onStepUp: { stepRenderSize(for: att, by: +1) },
                    topRounded: isFirst,
                    bottomRounded: isLast
                )
            }
        }
    }

    private func reorderBlock(draggedIdString: String, belowIndex: Int) {
        guard let id = UUID(uuidString: draggedIdString),
              let fromIdx = note.blocks.firstIndex(where: { $0.id == id }) else { return }
        let targetInsert = belowIndex + 1
        var reordered = note.blocks
        let block = reordered.remove(at: fromIdx)
        var adjusted = fromIdx < targetInsert ? targetInsert - 1 : targetInsert
        adjusted = max(0, min(adjusted, reordered.count))
        reordered.insert(block, at: adjusted)
        note.blocks = reordered
        note.updatedAt = Date()
    }

    // MARK: - Text binding

    private func textBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { note.blocks.indices.contains(index) ? note.blocks[index].textContent : "" },
            set: { newValue in
                guard note.blocks.indices.contains(index) else { return }
                var blocks = note.blocks
                blocks[index].textContent = newValue
                note.blocks = blocks
                note.updatedAt = Date()
            }
        )
    }

    // MARK: - Block navigation

    private func moveToPreviousAction(from index: Int, in blocks: [NoteBlock]) -> (() -> Void)? {
        for i in stride(from: index - 1, through: 0, by: -1) {
            if blocks[i].kind == .text {
                let id = blocks[i].id
                return { focusedEntryId.wrappedValue = id }
            }
        }
        return onMoveToPrevious
    }

    private func moveToNextAction(from index: Int, in blocks: [NoteBlock]) -> (() -> Void)? {
        for i in (index + 1)..<blocks.count {
            if blocks[i].kind == .text {
                let id = blocks[i].id
                return { focusedEntryId.wrappedValue = id }
            }
        }
        return onMoveToNext
    }

    // MARK: - Image block management

    // Inserts one or more image attachments at the focused text block, each followed by a new text block.
    private func insertImageBlocks(_ atts: [Attachment]) {
        var blocks = note.blocks
        if blocks.isEmpty { blocks = [.text("")] }

        let insertAfter: Int
        if let focusedId = focusedEntryId.wrappedValue,
           let focusedIdx = blocks.firstIndex(where: { $0.id == focusedId }),
           blocks[focusedIdx].kind == .text {
            insertAfter = focusedIdx
        } else {
            insertAfter = blocks.count - 1
        }

        var afterIdx = insertAfter
        var lastTextId: UUID?
        for att in atts {
            let imgBlock = NoteBlock.image(att.id)
            let txtBlock = NoteBlock.text("")
            blocks.insert(contentsOf: [imgBlock, txtBlock], at: afterIdx + 1)
            afterIdx += 2
            lastTextId = txtBlock.id
        }

        note.blocks = blocks
        if let id = lastTextId { focusedEntryId.wrappedValue = id }
    }

    private func deleteImageBlock(at index: Int, att: Attachment) {
        var blocks = note.blocks
        guard blocks.indices.contains(index), blocks[index].kind == .image else { return }
        blocks.remove(at: index)

        // Merge the surrounding text blocks (index−1 and index, post-removal)
        let prevIdx = index - 1
        let nextIdx = index
        if blocks.indices.contains(prevIdx), blocks.indices.contains(nextIdx),
           blocks[prevIdx].kind == .text, blocks[nextIdx].kind == .text {
            let combined = [
                blocks[prevIdx].textContent.trimmingCharacters(in: .newlines),
                blocks[nextIdx].textContent.trimmingCharacters(in: .newlines)
            ].filter { !$0.isEmpty }.joined(separator: "\n\n")
            blocks[prevIdx].textContent = combined
            blocks.remove(at: nextIdx)
        }

        note.blocks = blocks

        if let r = att.renderURL { AttachmentStorage.delete(at: r) }
        AttachmentStorage.delete(at: att.fileURL)
        modelContext.delete(att)
        note.attachments.removeAll { $0.id == att.id }
        note.updatedAt = Date()
    }

    // MARK: - File import

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let textExtensions: Set<String> = [
            "txt", "md", "markdown", "csv", "json", "yaml", "yml",
            "swift", "py", "js", "ts", "rb", "sh", "xml", "html", "htm"
        ]
        var newImageAtts: [Attachment] = []

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
                newImageAtts.append(att)
            }
        }

        if !newImageAtts.isEmpty { insertImageBlocks(newImageAtts) }
        note.updatedAt = Date()
    }

    // MARK: - Clipboard paste

    #if os(macOS)
    private func pasteImageFromClipboard() {
        let pb = NSPasteboard.general
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"]

        // Finder-copied file URLs
        var importedAtts: [Attachment] = []
        let fileURLs = (pb.readObjects(forClasses: [NSURL.self],
                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        for url in fileURLs where imageExts.contains(url.pathExtension.lowercased()) {
            let accessed = url.startAccessingSecurityScopedResource()
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            let fileId = UUID()
            let dest = AttachmentStorage.attachmentsDirectory
                .appendingPathComponent(fileId.uuidString)
                .appendingPathExtension(ext)
            let copied = (try? FileManager.default.copyItem(at: url, to: dest)) != nil
            if accessed { url.stopAccessingSecurityScopedResource() }
            guard copied else { continue }
            let att = Attachment(fileName: url.lastPathComponent, fileURL: dest, kind: .image)
            att.fileSizeBytes = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            att.note = note
            modelContext.insert(att)
            note.attachments.append(att)
            setupRender(for: att, sourceURL: dest)
            importedAtts.append(att)
        }
        if !importedAtts.isEmpty {
            insertImageBlocks(importedAtts)
            note.updatedAt = Date()
            return
        }

        // Raw PNG/TIFF data (screenshots, browser copy)
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
        insertImageBlocks([att])
        note.updatedAt = Date()
    }
    #endif

    // MARK: - PDF export

    #if os(macOS)
    private func exportAsPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedExportFilename()
        panel.message = "Export note as PDF"
        panel.prompt = "Export"

        panel.begin { [note] response in
            guard response == .OK, let url = panel.url else { return }
            let exportView = NoteExportView(note: note, date: note.dayRecord?.date)
            let hosting = NSHostingView(rootView: exportView)
            hosting.frame = .zero
            let size = hosting.fittingSize
            hosting.frame = CGRect(origin: .zero, size: size)
            let data = hosting.dataWithPDF(inside: hosting.bounds)
            try? data.write(to: url)
        }
    }

    private func suggestedExportFilename() -> String {
        for block in note.blocks where block.kind == .text {
            for rawLine in block.textContent.split(separator: "\n", omittingEmptySubsequences: true) {
                let line = String(rawLine)
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "^#+\\s+", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "[/:*?\"<>|\\\\]", with: "-", options: .regularExpression)
                if !line.isEmpty { return "\(String(line.prefix(60))).pdf" }
            }
        }
        if let date = note.dayRecord?.date {
            return "\(date.formatted(.iso8601.year().month().day()))-note.pdf"
        }
        return "note.pdf"
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
        if let oldRenderURL = att.renderURL { AttachmentStorage.delete(at: oldRenderURL) }
        att.renderURL = newRenderURL
        att.renderWidth = newWidth
        note.updatedAt = Date()
    }

    // MARK: - Non-image attachment strip

    @ViewBuilder private func nonImageAttachmentStrip(_ atts: [Attachment]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(atts) { att in
                NoteAttachmentRow(
                    attachment: att,
                    onPreview: { previewURL = att.fileURL },
                    onDelete: {
                        AttachmentStorage.delete(at: att.fileURL)
                        modelContext.delete(att)
                        note.attachments.removeAll { $0.id == att.id }
                        note.updatedAt = Date()
                    }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

// MARK: - NoteImageBlockRow

private struct NoteImageBlockRow: View {
    @Bindable var note: Note
    let block: NoteBlock
    let blockIndex: Int
    let att: Attachment
    let onPreview: () -> Void
    let onDelete: () -> Void
    let onStepDown: () -> Void
    let onStepUp: () -> Void
    var topRounded: Bool = true
    var bottomRounded: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 2)
                .padding(.top, topRounded ? 2 : 0)
                .padding(.bottom, bottomRounded ? 2 : 0)
            VStack(alignment: .leading, spacing: 6) {
                imageView
                controlsBar
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .background(
            Color.secondary.opacity(0.06),
            in: UnevenRoundedRectangle(
                topLeadingRadius:    topRounded    ? 6 : 0,
                bottomLeadingRadius: bottomRounded ? 6 : 0,
                bottomTrailingRadius: bottomRounded ? 6 : 0,
                topTrailingRadius:   topRounded    ? 6 : 0
            )
        )
    }

    @ViewBuilder private var imageView: some View {
        #if os(macOS)
        if let img = NSImage(contentsOf: att.renderURL ?? att.fileURL) {
            let maxW: CGFloat = 500
            let scale = min(maxW / img.size.width, 1.0)
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(width: img.size.width * scale)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
        }
        #endif
    }

    private var frameAlignment: Alignment {
        switch block.alignment {
        case .left:   .leading
        case .center: .center
        case .right:  .trailing
        }
    }

    @ViewBuilder private var controlsBar: some View {
        HStack(spacing: 6) {
            // Alignment
            ForEach(ImageAlignment.allCases, id: \.self) { alignment in
                Button { setAlignment(alignment) } label: {
                    Image(systemName: alignment.icon).font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(block.alignment == alignment ? Color.accentColor : Color.secondary.opacity(0.5))
            }

            // Size controls
            if let srcWidth = att.sourceImageWidth, let currentWidth = att.renderWidth {
                Divider().frame(height: 12)
                let steps = AttachmentStorage.renderSteps(forSourceWidth: srcWidth)
                let atMin = steps.first == currentWidth
                let atMax = steps.last == currentWidth
                Text("\(currentWidth)px").font(.caption2).foregroundStyle(.tertiary)
                Button { onStepDown() } label: { Image(systemName: "chevron.down").font(.caption2) }
                    .buttonStyle(.plain)
                    .foregroundStyle(atMin ? Color.secondary.opacity(0.3) : .secondary)
                    .disabled(atMin)
                Button { onStepUp() } label: { Image(systemName: "chevron.up").font(.caption2) }
                    .buttonStyle(.plain)
                    .foregroundStyle(atMax ? Color.secondary.opacity(0.3) : .secondary)
                    .disabled(atMax)
            }

            Divider().frame(height: 12)

            Button(action: onPreview) {
                Image(systemName: "eye").font(.caption)
            }.buttonStyle(.plain).foregroundStyle(.secondary)

            Button(action: onDelete) {
                Image(systemName: "xmark").font(.caption)
            }.buttonStyle(.plain).foregroundStyle(.red)

            Spacer()
        }
    }

    private func setAlignment(_ alignment: ImageAlignment) {
        var blocks = note.blocks
        guard blocks.indices.contains(blockIndex), blocks[blockIndex].kind == .image else { return }
        blocks[blockIndex].alignment = alignment
        note.blocks = blocks
        note.updatedAt = Date()
    }
}

// MARK: - NoteAttachmentRow (non-image files only)

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
            Image(systemName: icon).foregroundStyle(.secondary).font(.caption)
            Text(attachment.fileName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button(action: onPreview) {
                Image(systemName: "eye").font(.caption)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
            Button(action: onDelete) {
                Image(systemName: "xmark").font(.caption)
            }.buttonStyle(.plain).foregroundStyle(.red)
        }
    }
}
