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
    /// When false, the project/tags metadata rows are omitted (the host provides its own header,
    /// as in ContentNoteDetailView); the editing controls bar is still shown.
    var showsHeader: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(WorkspaceModel.self) private var workspace
    // Note-to-note linking is available in every editor: all content notes are the link pool,
    // titles resolve for chip labels, clicking a chip opens the edit modal, preview links navigate.
    @Query private var allNotesForLinks: [Note]

    @State private var isEditing = false
    @State private var narrowShowsPreview = false
    @State private var draft = ""
    @State private var showingImageImporter = false
    @State private var debouncer = Debouncer()
    @State private var previewDraft = ""
    @State private var previewDebouncer = Debouncer()
    @State private var editingImageID: UUID?
    @State private var showingDeleteConfirm = false
    @State private var chipRefresh = 0
    @State private var sourceHeight: CGFloat = 120
    @State private var autoFocusPending = false
    @State private var showingLinkPicker = false
    @State private var insertionText: String?
    @State private var insertionToken = 0
    @State private var editingLink: EditingLink?

    private struct EditingLink: Identifiable { let id: UUID }

    // Resolves a link chip's label from its target note: a meeting note shows the meeting summary
    // + date, a diary note its title, a content note its title.
    private func noteLinkTitle(_ id: UUID) -> String {
        guard let n = allNotesForLinks.first(where: { $0.id == id }) else { return "Note" }
        if let m = n.minutes {
            let summary = (m.summary?.isEmpty == false) ? m.summary! : "Meeting"
            return "\(summary) (\(m.meetingAt.formatted(.dateTime.month(.abbreviated).day())))"
        }
        return n.title.isEmpty ? "Untitled" : n.title
    }
    // Distinguishes a note-link tap (navigate) from a plain tap (enter edit mode) in the preview.
    // Class-based so the mutation is visible synchronously across the gesture closures (see CLAUDE.md).
    @State private var linkFlags = LinkTapFlags()
    @State private var previewTapCount = 0

    private final class LinkTapFlags { var didTapLink = false }
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
                    .simultaneousGesture(TapGesture().onEnded { previewTapCount += 1 })
                    .onChange(of: previewTapCount) {
                        // A note-link tap already navigated; suppress entering edit mode for it.
                        if linkFlags.didTapLink { linkFlags.didTapLink = false }
                        else { beginEditing() }
                    }
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
        .sheet(isPresented: $showingLinkPicker) {
            LinkPickerSheet(mode: .insert, onPick: { insertLink($0) })
        }
        .sheet(item: $editingLink) { link in
            LinkPickerSheet(
                mode: .edit(currentNoteID: link.id),
                onPick: { newID in changeLinkTarget(from: link.id, to: newID) },
                onRemove: { removeLink(link.id) }
            )
        }
        .alert("Delete Note?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the note and its content.")
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

    // Compact labeled metadata block, matching the meeting minutes metadata header. Insert-image
    // and Done controls sit at the top-right.
    @ViewBuilder
    private var header: some View {
        if showsHeader {
            VStack(alignment: .leading, spacing: 7) {
                if !note.title.isEmpty {
                    Text(note.title)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                metaRow("Project") { projectLine }
                metaRow("Tags")    { tagsLine }
            }
            .frame(maxWidth: .infinity, alignment: .leading)  // fill so chip vs placeholder width doesn't resize the card
            .padding(10)
            .background(AppTheme.cardRaised.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) { controlBar.padding(8) }
        } else {
            HStack(spacing: 8) { Spacer(minLength: 0); controlBar }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            if isEditing {
                Button { showingImageImporter = true } label: {
                    Image(systemName: "photo.badge.plus").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.action)
                .help("Insert image")
            }

            if isEditing {
                Button { showingLinkPicker = true } label: {
                    Image(systemName: "link.badge.plus").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.action)
                .help("Insert link")
            }

            if isEditing {
                Button { exitEditing() } label: {
                    Image(systemName: "checkmark.circle").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.action)
                .help("Done editing")
            }
            if onDelete != nil {
                Button { showingDeleteConfirm = true } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.action)
                .help("Delete note")
            }
        }
    }

    private func insertLink(_ id: UUID) {
        insertionText = NoteLinkRef.markdown(for: id, displayName: noteLinkTitle(id))
        insertionToken += 1
    }

    private func metaRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        // Center-aligned with a fixed min height (≈ chip height) so switching between a chip and the
        // placeholder text doesn't change the row height or shift it vertically.
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 22)
    }

    // Project chip when set; otherwise a tap-to-edit placeholder (only when editing is supported).
    @ViewBuilder
    private var projectLine: some View {
        if let project = note.project {
            Chip(label: project.name, color: AppTheme.project)
                .modifier(EditTapModifier(onEdit: onEdit))
        } else if onEdit != nil {
            metadataPlaceholder("None set — click to edit")
        } else {
            Text("—").font(.caption).foregroundStyle(.tertiary)
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
            metadataPlaceholder("None set — click to edit")
        } else {
            Text("—").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func metadataPlaceholder(_ text: String) -> some View {
        // Match the meeting minutes header's empty picker label: accent-colored, callout size.
        Text(text)
            .font(.callout)
            .foregroundStyle(AppTheme.accent)
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
                onTapImage: { editingImageID = $0 },
                noteTitle: { noteLinkTitle($0) },
                onTapNoteLink: { editingLink = EditingLink(id: $0) },
                insertionText: insertionText,
                insertionToken: insertionToken
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
            .environment(\.openURL, OpenURLAction { url in
                // Note links navigate to the target's home (content tab, diary day, or meeting tab
                // via reveal); the system handles everything else.
                if let id = NoteLinkRef.id(fromURL: url.absoluteString) {
                    linkFlags.didTapLink = true   // suppress the outer tap-to-edit for this tap
                    if let target = allNotesForLinks.first(where: { $0.id == id }) {
                        workspace.reveal(note: target)
                    }
                    return .handled
                }
                return .systemAction
            })
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

    // Repoint every link to `oldID` at `newID` (updating the displayed title to the new target).
    private func changeLinkTarget(from oldID: UUID, to newID: UUID) {
        guard oldID != newID else { editingLink = nil; return }
        let pattern = "\\[[^\\]]*\\]\\(note://\(oldID.uuidString)\\)"
        let replacement = NoteLinkRef.markdown(for: newID, displayName: noteLinkTitle(newID))
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        let updated = currentSource.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        applyLinkEdit(updated)
    }

    // Remove every link to `id` from the note markdown.
    private func removeLink(_ id: UUID) {
        let pattern = "\\[[^\\]]*\\]\\(note://\(id.uuidString)\\)"
        let updated = currentSource.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        applyLinkEdit(updated)
    }

    // The live editing text if editing, else the persisted content.
    private var currentSource: String { isEditing ? draft : note.content }

    private func applyLinkEdit(_ updated: String) {
        draft = updated
        previewDraft = updated
        note.content = updated
        note.updatedAt = Date()
        editingLink = nil
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
