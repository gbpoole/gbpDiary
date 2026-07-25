import SwiftUI
import SwiftData
import Textual
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// Adaptive markdown editor for a single `Note`.
//
// - When not editing: shows the rendered markdown preview (tap to edit).
// - When editing on a wide layout (Mac / iPad): source editor and live preview side by side.
// - When editing on a narrow layout (iPhone): source editor with an edit/preview toggle.
//
// Images are inserted as managed refs `![name](attachment://<uuid>)` — never file paths. The
// file is copied into the app container via `AttachmentStorage` and linked to the note.
struct MarkdownDocumentEditor: View {
    @Bindable var note: Note
    var placeholder: String = "Write in markdown…"
    var onEdit: (() -> Void)? = nil      // pencil → NoteEditorSheet (project/tags); hidden if nil
    var onDelete: (() -> Void)? = nil    // context-menu Delete; hidden if nil
    var startInEdit: Bool = false
    var onStartedEditing: (() -> Void)? = nil   // called once if startInEdit opens edit mode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var isEditing = false
    @State private var narrowShowsPreview = false
    @State private var draft = ""
    @State private var showingImageImporter = false
    @State private var debouncer = Debouncer()
    @State private var previewDraft = ""
    @State private var previewDebouncer = Debouncer()
    @State private var editingImageID: UUID?
    @State private var chipRefresh = 0
    @State private var sourceHeight: CGFloat = 120
    @State private var autoFocusPending = false
    #if os(macOS)
    @State private var escapeMonitor = EscapeKeyMonitor()
    #endif

    private var isWide: Bool { hSizeClass != .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if isEditing {
                editingBody
            } else {
                previewBody
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing() }
            }
        }
        .padding(10)
        .background(AppTheme.cardRaised.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            draft = note.content
            previewDraft = note.content
            if startInEdit {
                beginEditing()
                autoFocusPending = true
                onStartedEditing?()
            }
            #if os(macOS)
            escapeMonitor.action = {
                guard isEditing else { return false }
                exitEditing()
                return true
            }
            escapeMonitor.start()
            #endif
        }
        .onDisappear {
            commit()
            #if os(macOS)
            escapeMonitor.stop()
            #endif
        }
        .fileImporter(isPresented: $showingImageImporter,
                      allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { insertImages(from: urls) }
        }
        .sheet(item: Binding(get: { editingImageID.flatMap { id in note.attachments.first { $0.id == id } } },
                             set: { if $0 == nil { editingImageID = nil } })) { attachment in
            NoteImageEditSheet(attachment: attachment, onRemove: { removeImage(attachment.id) })
                .onDisappear { chipRefresh += 1 }  // refresh chips in case the display name changed
        }
        .contextMenu {
            #if os(macOS)
            if pasteboardHasImage {
                Button { pasteImageFromClipboard() } label: { Label("Paste Image", systemImage: "doc.on.clipboard") }
            }
            #endif
            if let onEdit { Button { onEdit() } label: { Label("Edit Tags & Project…", systemImage: "pencil") } }
            if let onDelete {
                Divider()
                Button(role: .destructive) { onDelete() } label: { Label("Delete Note", systemImage: "trash") }
            }
        }
    }

    // MARK: - Header (chips + controls)

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                projectLine
                Spacer(minLength: 6)
                Button { showingImageImporter = true } label: {
                    Image(systemName: "photo.badge.plus").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.action)
                .help("Insert image")
                if isEditing {
                    Button { exitEditing() } label: {
                        Image(systemName: "checkmark.circle").font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.action)
                    .help("Done editing")
                }
            }
            tagsLine
        }
    }

    // Project chip when set; otherwise a tap-to-edit placeholder (only when editing is supported).
    @ViewBuilder
    private var projectLine: some View {
        if let project = note.project {
            Chip(label: project.name, color: AppTheme.project)
                .modifier(EditTapModifier(onEdit: onEdit))
        } else if onEdit != nil {
            metadataPlaceholder("No project set — click to edit")
        }
    }

    // Tag chips when present; otherwise a tap-to-edit placeholder (only when editing is supported).
    @ViewBuilder
    private var tagsLine: some View {
        if !note.tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(note.tags, id: \.self) { tag in
                    Chip(label: tag, color: AppTheme.tag)
                }
            }
            .modifier(EditTapModifier(onEdit: onEdit))
        } else if onEdit != nil {
            metadataPlaceholder("No tags set — click to edit")
        }
    }

    private func metadataPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .contentShape(Rectangle())
            .onTapGesture { onEdit?() }
    }

    // Makes a set chip/chips tappable to re-open the project/tags editor, when one is available.
    private struct EditTapModifier: ViewModifier {
        let onEdit: (() -> Void)?
        func body(content: Content) -> some View {
            if let onEdit {
                content.contentShape(Rectangle()).onTapGesture { onEdit() }
            } else {
                content
            }
        }
    }

    // MARK: - Editing body (adaptive)

    @ViewBuilder
    private var editingBody: some View {
        if isWide {
            HStack(alignment: .top, spacing: 10) {
                sourceEditor
                    .frame(maxWidth: .infinity)
                Divider()
                previewBody
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Picker("", selection: $narrowShowsPreview) {
                    Text("Edit").tag(false)
                    Text("Preview").tag(true)
                }
                .pickerStyle(.segmented)
                if narrowShowsPreview { previewBody } else { sourceEditor }
            }
        }
    }

    @ViewBuilder
    private var sourceEditor: some View {
        Group {
            #if os(macOS)
            ImageChipTextEditor(
                text: $draft, height: $sourceHeight, attachments: note.attachments,
                refreshToken: chipRefresh,
                onInsertImageFiles: { urls, idx in insertRefs(urls.compactMap(makeImageRef), at: idx) },
                onInsertImageData: { data, idx in
                    if let ref = makeImageRef(fromPNG: data, displayName: "Pasted image") {
                        insertRefs([ref], at: idx)
                    }
                },
                startFocused: autoFocusPending,
                onTapImage: { editingImageID = $0 }
            )
            .frame(height: sourceHeight)
            #else
            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
            #endif
        }
        .padding(6)
        .background(AppTheme.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .onChange(of: draft) { _, newValue in
            // Persist on a longer debounce; refresh the live preview on a shorter one so typing
            // doesn't re-parse/re-render the Textual preview (and re-decode images) every keystroke.
            debouncer.schedule(delay: 1.0) {
                note.content = newValue
                note.updatedAt = Date()
            }
            previewDebouncer.schedule(delay: 0.3) { previewDraft = newValue }
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        if previewDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(placeholder)
                .foregroundStyle(.tertiary)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            StructuredText(
                markdown: NotePreviewMarkdown.render(previewDraft, resolve: fileURL(forAttachmentID:)),
                syntaxExtensions: [.math]
            )
            .textual.textSelection(.enabled)
            .textual.structuredTextStyle(.gitHub)
            .font(.body)
        }
    }

    // MARK: - Actions

    private func beginEditing() {
        draft = note.content
        previewDraft = note.content
        isEditing = true
    }

    private func exitEditing() {
        commit()
        isEditing = false
        autoFocusPending = false
        #if os(macOS)
        // Resign first responder so the caret leaves the source editor immediately.
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }

    private func commit() {
        debouncer.cancel()
        if note.content != draft {
            note.content = draft
            note.updatedAt = Date()
        }
    }

    private func fileURL(forAttachmentID id: UUID) -> URL? {
        note.attachments.first { $0.id == id }?.fileURL
    }

    // Remove an image ref from the note markdown and delete its attachment/file.
    private func removeImage(_ id: UUID) {
        let pattern = "!\\[[^\\]]*\\]\\(attachment://\(id.uuidString)\\)"
        draft = draft.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        note.content = draft
        if let att = note.attachments.first(where: { $0.id == id }) {
            AttachmentStorage.delete(at: att.fileURL)
            modelContext.delete(att)
        }
        note.updatedAt = Date()
        editingImageID = nil
    }

    // Create an Attachment for a source image file and return its markdown ref (no draft mutation).
    private func makeImageRef(from url: URL) -> String? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        let id = UUID()
        guard let stored = try? AttachmentStorage.store(from: url, fileId: id) else { return nil }
        let displayName = url.deletingPathExtension().lastPathComponent
        let attachment = Attachment(fileName: url.lastPathComponent, fileURL: stored, kind: .image, id: id)
        attachment.displayName = displayName
        attachment.fileSizeBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }
        attachment.note = note
        modelContext.insert(attachment)
        return AttachmentRef.markdown(for: id, displayName: displayName)
    }

    // Create an Attachment from raw PNG data (pasted/dropped image) and return its markdown ref.
    private func makeImageRef(fromPNG png: Data, displayName: String) -> String? {
        let id = UUID()
        let dest = AttachmentStorage.attachmentsDirectory
            .appendingPathComponent(id.uuidString).appendingPathExtension("png")
        guard (try? png.write(to: dest)) != nil else { return nil }
        let attachment = Attachment(fileName: dest.lastPathComponent, fileURL: dest, kind: .image, id: id)
        attachment.displayName = displayName
        attachment.fileSizeBytes = png.count
        attachment.note = note
        modelContext.insert(attachment)
        return AttachmentRef.markdown(for: id, displayName: displayName)
    }

    // Insert refs into `draft` at a UTF-16 index, separated from surrounding text by blank lines.
    // Changing draft (with lastMarkdown unchanged in the editor) forces the chip editor to rebuild.
    private func insertRefs(_ refs: [String], at index: Int) {
        guard !refs.isEmpty else { return }
        let joined = refs.joined(separator: "\n\n")
        let ns = draft as NSString
        let idx = max(0, min(index, ns.length))
        var prefix = "", suffix = ""
        if idx > 0, ns.substring(with: NSRange(location: idx - 1, length: 1)) != "\n" { prefix = "\n\n" }
        if idx < ns.length, ns.substring(with: NSRange(location: idx, length: 1)) != "\n" { suffix = "\n\n" }
        draft = ns.replacingCharacters(in: NSRange(location: idx, length: 0), with: prefix + joined + suffix)
        note.content = draft
        note.updatedAt = Date()
        isEditing = true
    }

    // Toolbar / file-importer path: append at the end.
    private func insertImages(from urls: [URL]) {
        insertRefs(urls.compactMap(makeImageRef), at: (draft as NSString).length)
    }

    #if os(macOS)
    private var pasteboardHasImage: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    private func pasteImageFromClipboard() {
        guard let png = NSPasteboard.general.imagePNGData(),
              let ref = makeImageRef(fromPNG: png, displayName: "Pasted image") else { return }
        insertRefs([ref], at: (draft as NSString).length)
    }
    #endif
}
