import SwiftUI

#if os(macOS)
import AppKit
import ImageIO
import UniformTypeIdentifiers

extension NSPasteboard {
    // PNG data for a pasted/dropped raw image (e.g. a screenshot), or nil if none. Tries explicit image
    // data types on the pasteboard first (many apps put a `public.png`/`.tiff`/`.jpeg` payload that
    // `NSImage(pasteboard:)` won't always read), then falls back to `NSImage(pasteboard:)`.
    func imagePNGData() -> Data? {
        let dataTypes: [NSPasteboard.PasteboardType] = [
            .png, .tiff,
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
            NSPasteboard.PasteboardType(UTType.heic.identifier),
        ]
        for type in dataTypes {
            if let data = data(forType: type), let png = NSPasteboard.pngData(fromImageData: data) {
                return png
            }
        }
        if let image = NSImage(pasteboard: self), let tiff = image.tiffRepresentation {
            return NSPasteboard.pngData(fromImageData: tiff)
        }
        return nil
    }

    // Normalise arbitrary image data (png/tiff/jpeg/heic/…) to PNG via a bitmap rep.
    private static func pngData(fromImageData data: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// An NSTextView-backed markdown editor that renders managed image refs
// `![name](attachment://<uuid>)` as atomic, non-editable image chips (thumbnail + name). All other
// text is plain, editable markdown. Chips serialize back to markdown, and clicking one calls
// `onTapImage`. This is the one place the app keeps a custom text view (see CLAUDE.md).
struct ImageChipTextEditor: NSViewRepresentable {
    @Binding var text: String
    /// Measured content height, pushed back to SwiftUI so the editor grows with its content without
    /// participating in (and looping) SwiftUI's layout negotiation.
    @Binding var height: CGFloat
    var attachments: [Attachment]
    /// Bump to force a chip rebuild (e.g. after a display name is edited) without a text change.
    var refreshToken: Int
    /// Dropped/pasted image files → create attachments and insert refs at the given UTF-16 index.
    var onInsertImageFiles: ([URL], Int) -> Void
    /// Dropped/pasted raw image data (e.g. a screenshot) → insert a ref at the given UTF-16 index.
    var onInsertImageData: (Data, Int) -> Void
    /// When true, focus the editor with the caret at the start once it appears.
    var startFocused: Bool = false
    var onTapImage: (UUID) -> Void
    /// Reports the caret's **markdown** offset as the selection changes, so the host can insert images
    /// from the toolbar / clipboard menu at the caret rather than the end of the note.
    var onCaretChange: ((Int) -> Void)? = nil
    /// Resolves the current title of a linked note (for the chip label). nil disables note-link chips.
    var noteTitle: ((UUID) -> String)? = nil
    /// Called when a note-link chip is clicked.
    var onTapNoteLink: ((UUID) -> Void)? = nil
    /// Markdown fragment to insert at the caret; paired with `insertionToken` so a repeat of the
    /// same text still triggers. The host bumps the token to request an insertion.
    var insertionText: String? = nil
    var insertionToken: Int = 0
    /// When true the editor handles formatting shortcuts (⌘B, etc.) and applies toolbar commands.
    var formattingEnabled: Bool = false
    /// A formatting command to apply at the current selection; paired with `formatToken` (the host
    /// bumps the token to request it), mirroring the `insertionText`/`insertionToken` pattern.
    var formatCommand: FormatCommand? = nil
    var formatToken: Int = 0
    /// Insert text on a new line after the caret's line (continuing a list marker if applicable),
    /// paired with `newLineInsertionToken`.
    var newLineInsertion: String? = nil
    var newLineInsertionToken: Int = 0

    static let minHeight: CGFloat = 120

    private static let refRegex = try! NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\(attachment://([0-9A-Fa-f-]{36})\)"#
    )
    private static let noteRefRegex = try! NSRegularExpression(
        pattern: #"\[([^\]]*)\]\(note://([0-9A-Fa-f-]{36})\)"#
    )

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // A plain (non-scrolling) text view sized by SwiftUI to its measured content height (see the
    // `height` binding). No NSScrollView — an autohiding scroller would flip on/off at the content
    // boundary, changing the text width and reflowing height, which oscillates. No content-based
    // `sizeThatFits` either — that renegotiates height with SwiftUI every keystroke and, alongside
    // the self-sizing preview, storms the layout system. Height is pushed one-way instead.
    func makeNSView(context: Context) -> ChipTextView {
        let tv = ChipTextView()
        tv.delegate = context.coordinator
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = true          // required so attachments render
        tv.importsGraphics = false
        tv.drawsBackground = false
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.font = Self.bodyFont
        tv.typingAttributes = Self.textAttributes
        // Spell-check while editing (minutes); no autocorrect/substitutions that would mangle markdown.
        tv.isContinuousSpellCheckingEnabled = formattingEnabled
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.onTapImage = onTapImage
        tv.onTapNoteLink = onTapNoteLink
        tv.onInsertImageFiles = onInsertImageFiles
        tv.onInsertImageData = onInsertImageData
        tv.onWidthChange = { [weak coordinator = context.coordinator] in coordinator?.scheduleHeightPush() }
        tv.formattingEnabled = formattingEnabled
        tv.onFormatCommand = { [weak coordinator = context.coordinator] cmd in
            guard let c = coordinator, let tv = c.textView else { return }
            c.applyFormat(cmd, into: tv)
        }
        tv.onReturn = { [weak coordinator = context.coordinator] in
            guard let c = coordinator, let tv = c.textView else { return false }
            return c.handleReturn(in: tv)
        }
        tv.onIndent = { [weak coordinator = context.coordinator] outdent in
            guard let c = coordinator, let tv = c.textView else { return false }
            return c.handleIndent(outdent: outdent, in: tv)
        }
        tv.onBackspace = { [weak coordinator = context.coordinator] in
            guard let c = coordinator, let tv = c.textView else { return false }
            return c.handleBackspace(in: tv)
        }
        context.coordinator.textView = tv
        context.coordinator.lastInsertionToken = insertionToken
        context.coordinator.lastFormatToken = formatToken
        context.coordinator.lastNewLineToken = newLineInsertionToken
        context.coordinator.apply(markdown: text, into: tv)
        if startFocused {
            DispatchQueue.main.async { [weak tv] in
                guard let tv, let window = tv.window else { return }
                window.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: 0, length: 0))
            }
        }
        return tv
    }

    func updateNSView(_ tv: ChipTextView, context: Context) {
        context.coordinator.parent = self
        tv.onTapImage = onTapImage
        tv.onTapNoteLink = onTapNoteLink
        tv.onInsertImageFiles = onInsertImageFiles
        tv.onInsertImageData = onInsertImageData
        tv.formattingEnabled = formattingEnabled
        // Rebuild on an explicit refresh (e.g. a chip's display name changed), or on a *genuine* external
        // text change — never for a stale echo of the user's own in-flight typing (which would revert the
        // buffer and jump the caret). See MarkdownEditorSync.
        if refreshToken != context.coordinator.lastRefresh {
            context.coordinator.lastRefresh = refreshToken
            // Refresh only fires after the image-edit sheet closes (not mid-type). Rebuild from the
            // buffer's current serialized content so any un-echoed in-flight typing isn't lost, and the
            // new chip labels from `attachments` are picked up.
            if let storage = tv.textStorage {
                context.coordinator.apply(markdown: context.coordinator.serialize(storage), into: tv)
            }
            context.coordinator.pendingEchoes.removeAll()
        } else if MarkdownEditorSync.shouldRebuild(incoming: text,
                                                   buffer: context.coordinator.lastMarkdown,
                                                   pendingEchoes: &context.coordinator.pendingEchoes) {
            context.coordinator.apply(markdown: text, into: tv)
        }
        // Host requested a caret insertion (e.g. a note link picked from the picker).
        if insertionToken != context.coordinator.lastInsertionToken {
            context.coordinator.lastInsertionToken = insertionToken
            if let fragment = insertionText, !fragment.isEmpty {
                context.coordinator.insert(fragment, into: tv)
            }
        }
        // Host requested a formatting command from the toolbar.
        if formatToken != context.coordinator.lastFormatToken {
            context.coordinator.lastFormatToken = formatToken
            if let command = formatCommand {
                context.coordinator.applyFormat(command, into: tv)
            }
        }
        // Host requested a new-line insertion (e.g. a meeting action line).
        if newLineInsertionToken != context.coordinator.lastNewLineToken {
            context.coordinator.lastNewLineToken = newLineInsertionToken
            if let text = newLineInsertion, !text.isEmpty {
                context.coordinator.insertOnNewLine(text, into: tv)
            }
        }
    }

    // MARK: - Shared styling

    static let bodyFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: NSColor.labelColor]
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ImageChipTextEditor
        weak var textView: ChipTextView?
        var lastMarkdown = ""
        var lastRefresh = Int.min
        var lastInsertionToken = Int.min
        var lastFormatToken = Int.min
        var lastNewLineToken = Int.min
        // Self-originated markdown pushes that SwiftUI hasn't reconciled back through updateNSView yet.
        // Lets updateNSView tell a stale echo of our own typing from a genuine external change — see
        // MarkdownEditorSync. Capped so a coalesced push that never round-trips can't grow it unbounded.
        var pendingEchoes: [String] = []
        private var heightPushScheduled = false

        init(_ parent: ImageChipTextEditor) { self.parent = parent }

        // Push a self-originated edit back to the SwiftUI binding on the next run-loop tick (deferred to
        // let AppKit finish its edit cycle first; a synchronous mutation re-enters layout and storms it),
        // recording it as a pending echo so updateNSView won't mistake the lagging value for an external
        // change and revert the buffer.
        func pushMarkdownToSwiftUI(_ markdown: String) {
            pendingEchoes.append(markdown)
            if pendingEchoes.count > 32 { pendingEchoes.removeFirst(pendingEchoes.count - 32) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.text != markdown { self.parent.text = markdown }
            }
        }

        // Measure the laid-out content height and push it to SwiftUI (coalesced, deferred). Done
        // outside SwiftUI's layout pass so it never re-enters/loops sizing.
        func scheduleHeightPush() {
            guard !heightPushScheduled else { return }
            heightPushScheduled = true
            DispatchQueue.main.async { [weak self] in
                self?.heightPushScheduled = false
                self?.pushHeight()
            }
        }

        private func pushHeight() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let measured = ceil(lm.usedRect(for: tc).height) + tv.textContainerInset.height * 2
            let clamped = max(ImageChipTextEditor.minHeight, measured)
            if abs(parent.height - clamped) > 0.5 { parent.height = clamped }
        }

        // A ref match tagged with its kind, so image and note-link refs can be processed in one
        // left-to-right pass over the markdown.
        private enum RefKind { case image, noteLink }
        private struct RefMatch { let range: NSRange; let text: String; let id: UUID; let kind: RefKind }

        // Build an attributed string from markdown, swapping image and note-link refs for chips.
        func apply(markdown: String, into tv: ChipTextView) {
            let attr = NSMutableAttributedString()
            let ns = markdown as NSString
            let full = NSRange(location: 0, length: ns.length)

            var refs: [RefMatch] = []
            for m in ImageChipTextEditor.refRegex.matches(in: markdown, range: full) {
                if let id = UUID(uuidString: ns.substring(with: m.range(at: 2))) {
                    refs.append(RefMatch(range: m.range, text: ns.substring(with: m.range(at: 1)), id: id, kind: .image))
                }
            }
            if parent.noteTitle != nil {
                for m in ImageChipTextEditor.noteRefRegex.matches(in: markdown, range: full) {
                    if let id = UUID(uuidString: ns.substring(with: m.range(at: 2))) {
                        refs.append(RefMatch(range: m.range, text: ns.substring(with: m.range(at: 1)), id: id, kind: .noteLink))
                    }
                }
            }
            refs.sort { $0.range.location < $1.range.location }

            var cursor = 0
            for ref in refs {
                if ref.range.location < cursor { continue }  // defensive: skip any overlap
                if ref.range.location > cursor {
                    let sub = ns.substring(with: NSRange(location: cursor, length: ref.range.location - cursor))
                    attr.append(NSAttributedString(string: sub, attributes: ImageChipTextEditor.textAttributes))
                }
                let chipString = NSMutableAttributedString(attachment: chipAttachment(for: ref))
                // Carry the editor's font/color on the attachment character so text typed right
                // after a chip inherits the monospace font and label color (not the defaults).
                chipString.addAttributes(ImageChipTextEditor.textAttributes,
                                         range: NSRange(location: 0, length: chipString.length))
                attr.append(chipString)
                cursor = ref.range.location + ref.range.length
            }
            if cursor < ns.length {
                attr.append(NSAttributedString(string: ns.substring(from: cursor), attributes: ImageChipTextEditor.textAttributes))
            }
            let selected = tv.selectedRange()
            tv.textStorage?.setAttributedString(attr)
            tv.typingAttributes = ImageChipTextEditor.textAttributes
            if selected.location <= attr.length {
                tv.setSelectedRange(NSRange(location: min(selected.location, attr.length), length: 0))
            }
            lastMarkdown = markdown
            scheduleHeightPush()
        }

        private func chipAttachment(for ref: RefMatch) -> NSTextAttachment {
            switch ref.kind {
            case .image:
                let attachment = parent.attachments.first { $0.id == ref.id }
                let name = attachment?.displayName ?? attachment?.fileName ?? ref.text
                return ImageRefAttachment(imageID: ref.id, displayName: name,
                                          image: Self.chipImage(for: attachment, name: name))
            case .noteLink:
                let title = parent.noteTitle?(ref.id) ?? ref.text
                let name = title.isEmpty ? "Note" : title
                return NoteLinkRefAttachment(noteID: ref.id, displayName: name,
                                             image: Self.noteChipImage(name: name))
            }
        }

        // Serialize the attributed string back to markdown: chips become their ref, text stays text.
        func serialize(_ storage: NSAttributedString) -> String {
            var out = ""
            let full = NSRange(location: 0, length: storage.length)
            storage.enumerateAttribute(.attachment, in: full) { value, range, _ in
                if let chip = value as? ImageRefAttachment {
                    out += AttachmentRef.markdown(for: chip.imageID, displayName: chip.displayName)
                } else if let chip = value as? NoteLinkRefAttachment {
                    out += NoteLinkRef.markdown(for: chip.noteID, displayName: chip.displayName)
                } else {
                    out += storage.attributedSubstring(from: range).string
                }
            }
            return out
        }

        // Insert a markdown fragment at the caret (as plain text), then serialize + rebuild so any
        // ref in the fragment becomes a chip. Defers the SwiftUI text push to avoid mutating state
        // during a view update.
        func insert(_ fragment: String, into tv: ChipTextView) {
            guard let storage = tv.textStorage else { return }
            let range = tv.selectedRange()
            let attrFragment = NSAttributedString(string: fragment, attributes: ImageChipTextEditor.textAttributes)
            storage.replaceCharacters(in: range, with: attrFragment)
            tv.setSelectedRange(NSRange(location: range.location + attrFragment.length, length: 0))
            let markdown = serialize(storage)
            apply(markdown: markdown, into: tv)  // rebuild so the inserted ref renders as a chip
            pushMarkdownToSwiftUI(markdown)
        }

        // Apply a formatting command to the current selection. Works on the text view's *display*
        // string (chips are single U+FFFC placeholder characters) via the pure `MarkdownFormatting`
        // helper, then rebuilds the attributed string restoring chips in order (formatting never
        // adds/removes chips). Undoable, and serialized back to the markdown binding like `insert`.
        func applyFormat(_ command: FormatCommand, into tv: ChipTextView) {
            applyResult(MarkdownFormatting.apply(command, to: tv.string, selection: tv.selectedRange()), into: tv)
        }

        // Continue a markdown list when Return is pressed on a list item (new item + indent, or end
        // the list on an empty item). Returns true when handled, so the text view skips its default
        // newline; false falls through to a normal newline.
        func handleReturn(in tv: ChipTextView) -> Bool {
            guard let result = MarkdownFormatting.returnInList(text: tv.string, selection: tv.selectedRange()) else { return false }
            applyResult(result, into: tv)
            return true
        }

        // Tab / Shift-Tab: indent or outdent list items. Returns false (fall through) on non-list lines.
        func handleIndent(outdent: Bool, in tv: ChipTextView) -> Bool {
            guard let result = MarkdownFormatting.indentLines(text: tv.string, selection: tv.selectedRange(), outdent: outdent) else { return false }
            applyResult(result, into: tv)
            return true
        }

        // Insert text on a new line after the caret's line (continuing a list marker if applicable).
        func insertOnNewLine(_ text: String, into tv: ChipTextView) {
            applyResult(MarkdownFormatting.insertOnNewLine(text: tv.string, selection: tv.selectedRange(), insert: text), into: tv)
        }

        // Backspace at a list marker: outdent one level or clear the marker.
        func handleBackspace(in tv: ChipTextView) -> Bool {
            guard let result = MarkdownFormatting.backspaceInList(text: tv.string, selection: tv.selectedRange()) else { return false }
            applyResult(result, into: tv)
            return true
        }

        // Apply a MarkdownFormatting result to the text view: rebuild the attributed string restoring
        // chips in order (formatting never adds/removes chips), undoably, then restore the selection
        // and serialize back to the markdown binding like `insert`.
        func applyResult(_ result: MarkdownFormatting.Result, into tv: ChipTextView) {
            guard let storage = tv.textStorage else { return }

            // Existing chips in document order, to re-attach at the placeholder characters.
            var chips: [NSTextAttachment] = []
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                if let a = value as? NSTextAttachment { chips.append(a) }
            }
            let attachmentChar: unichar = 0xFFFC
            let rebuilt = NSMutableAttributedString()
            let ns = result.text as NSString
            var chipIndex = 0
            var runStart = 0
            for i in 0..<ns.length {
                if ns.character(at: i) == attachmentChar {
                    if i > runStart {
                        rebuilt.append(NSAttributedString(string: ns.substring(with: NSRange(location: runStart, length: i - runStart)),
                                                          attributes: ImageChipTextEditor.textAttributes))
                    }
                    if chipIndex < chips.count {
                        let chipStr = NSMutableAttributedString(attachment: chips[chipIndex])
                        chipStr.addAttributes(ImageChipTextEditor.textAttributes, range: NSRange(location: 0, length: chipStr.length))
                        rebuilt.append(chipStr)
                        chipIndex += 1
                    }
                    runStart = i + 1
                }
            }
            if runStart < ns.length {
                rebuilt.append(NSAttributedString(string: ns.substring(from: runStart),
                                                  attributes: ImageChipTextEditor.textAttributes))
            }

            let full = NSRange(location: 0, length: storage.length)
            guard tv.shouldChangeText(in: full, replacementString: result.text) else { return }
            storage.setAttributedString(rebuilt)
            tv.typingAttributes = ImageChipTextEditor.textAttributes
            let selLoc = min(result.selection.location, rebuilt.length)
            let selLen = min(result.selection.length, rebuilt.length - selLoc)
            tv.setSelectedRange(NSRange(location: selLoc, length: selLen))
            tv.didChangeText()

            let markdown = serialize(storage)
            lastMarkdown = markdown
            scheduleHeightPush()
            pushMarkdownToSwiftUI(markdown)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let onCaretChange = parent.onCaretChange,
                  let tv = notification.object as? ChipTextView else { return }
            onCaretChange(tv.markdownIndex(forDisplayLocation: tv.selectedRange().location))
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let markdown = serialize(storage)
            lastMarkdown = markdown
            // Push to SwiftUI on the next run-loop tick (deferred so AppKit finishes its edit cycle first;
            // a synchronous mutation re-runs sizeThatFits/ensureLayout re-entrantly and storms layout).
            // Recorded as a pending echo so the lagging value isn't mistaken for an external change.
            pushMarkdownToSwiftUI(markdown)
            DispatchQueue.main.async { [weak self] in self?.pushHeight() }
        }

        // MARK: Chip rendering

        // Cached, downsampled thumbnails keyed by attachment id. Decoding the full-resolution
        // source on the main thread (images are stored uncapped) would beach-ball the editor, so we
        // use ImageIO to decode a small thumbnail and reuse it across chip rebuilds.
        private static var thumbnailCache: [UUID: NSImage] = [:]

        static func thumbnail(for attachment: Attachment) -> NSImage? {
            if let cached = thumbnailCache[attachment.id] { return cached }
            guard let source = CGImageSourceCreateWithURL(attachment.fileURL as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 40,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            thumbnailCache[attachment.id] = image
            return image
        }

        static func chipImage(for attachment: Attachment?, name: String) -> NSImage {
            let height: CGFloat = 22
            let thumb: CGFloat = 16
            let hPad: CGFloat = 8
            let gap: CGFloat = 5
            let neutral = NSColor.secondaryLabelColor
            let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
            let nameAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            let displayName = name.isEmpty ? "image" : name
            let nameSize = (displayName as NSString).size(withAttributes: nameAttrs)
            let width = hPad + thumb + gap + ceil(nameSize.width) + hPad

            let image = NSImage(size: NSSize(width: width, height: height))
            image.lockFocus()
            let radius = height / 2
            let bgRect = NSRect(x: 0, y: 0, width: width, height: height)
            neutral.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius).fill()
            let border = NSBezierPath(roundedRect: bgRect.insetBy(dx: 0.5, dy: 0.5),
                                      xRadius: radius, yRadius: radius)
            border.lineWidth = 1
            neutral.withAlphaComponent(0.45).setStroke()
            border.stroke()

            let thumbRect = NSRect(x: hPad, y: (height - thumb) / 2, width: thumb, height: thumb)
            if let thumbImage = attachment.flatMap({ thumbnail(for: $0) }) {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: thumbRect, xRadius: 3, yRadius: 3).addClip()
                thumbImage.draw(in: thumbRect, from: .zero, operation: .sourceOver, fraction: 1,
                                respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
            } else if let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
                symbol.draw(in: thumbRect)
            }
            (displayName as NSString).draw(
                at: NSPoint(x: hPad + thumb + gap, y: (height - nameSize.height) / 2),
                withAttributes: nameAttrs
            )
            image.unlockFocus()
            return image
        }

        // A text-only pill for a note-to-note link: a small link glyph + the target note's title.
        // Sized to exactly one text line's height so inserting/removing a link never changes the
        // line height (which would shift the text below).
        static func noteChipImage(name: String) -> NSImage {
            let height = ceil(NSLayoutManager().defaultLineHeight(for: ImageChipTextEditor.bodyFont))
            let icon: CGFloat = 10
            let hPad: CGFloat = 7
            let gap: CGFloat = 3
            let tint = NSColor.systemBlue
            let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
            let nameAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: tint]
            let displayName = name.isEmpty ? "Note" : name
            let nameSize = (displayName as NSString).size(withAttributes: nameAttrs)
            let width = hPad + icon + gap + ceil(nameSize.width) + hPad

            let image = NSImage(size: NSSize(width: width, height: height))
            image.lockFocus()
            let radius = height / 2
            let bgRect = NSRect(x: 0, y: 0, width: width, height: height)
            tint.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius).fill()
            let border = NSBezierPath(roundedRect: bgRect.insetBy(dx: 0.5, dy: 0.5),
                                      xRadius: radius, yRadius: radius)
            border.lineWidth = 1
            tint.withAlphaComponent(0.45).setStroke()
            border.stroke()

            let iconRect = NSRect(x: hPad, y: (height - icon) / 2, width: icon, height: icon)
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            if let symbol = NSImage(systemSymbolName: "link", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let tinted = symbol.copy() as! NSImage
                tinted.lockFocus()
                tint.set()
                NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                tinted.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1,
                            respectFlipped: true, hints: nil)
            }
            (displayName as NSString).draw(
                at: NSPoint(x: hPad + icon + gap, y: (height - nameSize.height) / 2),
                withAttributes: nameAttrs
            )
            image.unlockFocus()
            return image
        }
    }
}

// NSTextAttachment carrying the target note id + display title for round-tripping to markdown.
final class NoteLinkRefAttachment: NSTextAttachment {
    let noteID: UUID
    let displayName: String

    init(noteID: UUID, displayName: String, image: NSImage) {
        self.noteID = noteID
        self.displayName = displayName
        super.init(data: nil, ofType: nil)
        self.image = image
        // Sit within the line's box (descender → up) so the chip occupies exactly one line height
        // and never grows the line — inserting/removing a link then doesn't shift the text below.
        let font = ImageChipTextEditor.bodyFont
        self.bounds = CGRect(x: 0, y: floor(font.descender),
                             width: image.size.width, height: image.size.height)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// NSTextAttachment carrying the managed-image id + display name for round-tripping to markdown.
final class ImageRefAttachment: NSTextAttachment {
    let imageID: UUID
    let displayName: String

    init(imageID: UUID, displayName: String, image: NSImage) {
        self.imageID = imageID
        self.displayName = displayName
        super.init(data: nil, ofType: nil)
        self.image = image
        // Vertically centre the chip on the line's ascender/descender midline.
        let font = ImageChipTextEditor.bodyFont
        let mid = (font.ascender + font.descender) / 2
        self.bounds = CGRect(x: 0, y: mid - image.size.height / 2,
                             width: image.size.width, height: image.size.height)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// NSTextView that reports clicks on image chips instead of placing the caret there.
final class ChipTextView: NSTextView {
    var onTapImage: ((UUID) -> Void)?
    var onTapNoteLink: ((UUID) -> Void)?
    var onWidthChange: (() -> Void)?
    var onInsertImageFiles: (([URL], Int) -> Void)?
    var onInsertImageData: ((Data, Int) -> Void)?
    var formattingEnabled = false
    var onFormatCommand: ((FormatCommand) -> Void)?
    var onReturn: (() -> Bool)?
    var onIndent: ((Bool) -> Bool)?     // outdent flag → handled?
    var onBackspace: (() -> Bool)?
    private var lastWidth: CGFloat = 0

    // Smart list continuation: on a list item, Return starts the next item (or ends the list). The
    // handler returns true when it consumed the key; otherwise fall back to the normal newline.
    override func insertNewline(_ sender: Any?) {
        if formattingEnabled, onReturn?() == true { return }
        super.insertNewline(sender)
    }

    // Tab / Shift-Tab indent or outdent list items (falls through on non-list lines).
    override func insertTab(_ sender: Any?) {
        if formattingEnabled, onIndent?(false) == true { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if formattingEnabled, onIndent?(true) == true { return }
        super.insertBacktab(sender)
    }

    // Backspace at a list marker outdents / clears the marker (falls through otherwise).
    override func deleteBackward(_ sender: Any?) {
        if formattingEnabled, onBackspace?() == true { return }
        super.deleteBackward(sender)
    }

    // Intercept formatting shortcuts before NSTextView's rich-text handling (e.g. ⌘B → NSFontManager
    // bold) so they insert markdown instead. Only when formatting is enabled for this editor.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if formattingEnabled, let command = ChipTextView.formatCommand(for: event) {
            onFormatCommand?(command)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    static func formatCommand(for event: NSEvent) -> FormatCommand? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return nil }
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (key, shift, option) {
        case ("b", false, false): return .bold
        case ("i", false, false): return .italic
        case ("c", true, false):  return .inlineCode
        case ("l", true, false):  return .bulletList
        case ("o", true, false):  return .numberedList
        case ("u", true, false):  return .checkbox
        case ("q", true, false):  return .quote
        case ("t", true, false):  return .table
        case ("1", false, true):  return .heading(1)
        case ("2", false, true):  return .heading(2)
        case ("3", false, true):  return .heading(3)
        default: return nil
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if abs(newSize.width - lastWidth) > 0.5 {
            lastWidth = newSize.width
            onWidthChange?()   // content reflows at the new width → re-measure height
        }
    }

    // MARK: - Copy / cut / paste

    // Private pasteboard type carrying the serialized markdown of a copied/cut selection, so image and
    // link chips round-trip (a plain RTFD copy loses our managed attachments). We also write `.string`
    // for pasting into other apps.
    static let chipMarkdownType = NSPasteboard.PasteboardType("com.gbpdiary.note-markdown")

    private var chipCoordinator: ImageChipTextEditor.Coordinator? {
        delegate as? ImageChipTextEditor.Coordinator
    }

    // Serialize the current selection to markdown and place it on the pasteboard. Returns false when
    // there's no selection (caller falls back to the default behaviour).
    @discardableResult
    private func writeSelectionMarkdown() -> Bool {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage, let coord = chipCoordinator else { return false }
        let markdown = coord.serialize(storage.attributedSubstring(from: range))
        guard !markdown.isEmpty else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(markdown, forType: ChipTextView.chipMarkdownType)
        pb.setString(markdown, forType: .string)
        return true
    }

    override func copy(_ sender: Any?) {
        if !writeSelectionMarkdown() { super.copy(sender) }
    }

    override func cut(_ sender: Any?) {
        guard writeSelectionMarkdown() else { super.cut(sender); return }
        let range = selectedRange()
        if shouldChangeText(in: range, replacementString: "") {
            textStorage?.replaceCharacters(in: range, with: "")
            didChangeText()   // serialize + push the updated markdown to SwiftUI
        }
    }

    // NSTextView only enables Paste (⌘V) when the pasteboard has a type it considers readable — by
    // default text/RTF/RTFD only. Advertise image + file-URL + our chip-markdown types so an image-only
    // clipboard (e.g. a screen capture) doesn't disable Paste and beep before `paste(_:)` can run.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [
            ChipTextView.chipMarkdownType, .fileURL, .png, .tiff,
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
            NSPasteboard.PasteboardType(UTType.heic.identifier),
        ]
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        // Our own copied/cut selection: re-insert as markdown so chips (image/link) are rebuilt.
        if let markdown = pb.string(forType: ChipTextView.chipMarkdownType), let coord = chipCoordinator {
            coord.insert(markdown, into: self); return
        }
        let index = markdownIndex(forDisplayLocation: selectedRange().location)
        if let urls = ChipTextView.imageFileURLs(from: pb), !urls.isEmpty {
            onInsertImageFiles?(urls, index); return
        }
        if let data = pb.imagePNGData() {
            onInsertImageData?(data, index); return
        }
        super.paste(sender)
    }

    // Converts a location in the *display* string (chips are single U+FFFC placeholders) into the
    // offset in the serialized *markdown* string, so inserts land at the right place once the note
    // already contains chips (see ChipMarkdownOffset).
    func markdownIndex(forDisplayLocation loc: Int) -> Int {
        guard let storage = textStorage else { return loc }
        var runs: [ChipRun] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            let markdownLength: Int
            if let chip = value as? ImageRefAttachment {
                markdownLength = (AttachmentRef.markdown(for: chip.imageID, displayName: chip.displayName) as NSString).length
            } else if let chip = value as? NoteLinkRefAttachment {
                markdownLength = (NoteLinkRef.markdown(for: chip.noteID, displayName: chip.displayName) as NSString).length
            } else {
                markdownLength = range.length
            }
            runs.append(ChipRun(displayLength: range.length, markdownLength: markdownLength))
        }
        return ChipMarkdownOffset.markdownOffset(displayLocation: loc, runs: runs)
    }

    // MARK: - Image drag & drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        ChipTextView.hasDroppableImage(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        ChipTextView.hasDroppableImage(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let point = convert(sender.draggingLocation, from: nil)
        let index = markdownIndex(forDisplayLocation: characterIndexForInsertion(at: point))
        if let urls = ChipTextView.imageFileURLs(from: pb), !urls.isEmpty {
            onInsertImageFiles?(urls, index); return true
        }
        if let data = pb.imagePNGData() {
            onInsertImageData?(data, index); return true
        }
        return super.performDragOperation(sender)
    }

    private static func hasDroppableImage(_ pb: NSPasteboard) -> Bool {
        if let urls = imageFileURLs(from: pb), !urls.isEmpty { return true }
        return pb.canReadItem(withDataConformingToTypes: [UTType.image.identifier])
    }

    private static func imageFileURLs(from pb: NSPasteboard) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else { return nil }
        return urls.filter { url in
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let lm = layoutManager, let tc = textContainer, let ts = textStorage, ts.length > 0 else {
            super.mouseDown(with: event); return
        }
        var point = convert(event.locationInWindow, from: nil)
        let origin = textContainerOrigin
        point.x -= origin.x; point.y -= origin.y
        let glyph = lm.glyphIndex(for: point, in: tc)
        let charIdx = lm.characterIndexForGlyph(at: glyph)
        if charIdx < ts.length {
            let attachment = ts.attribute(.attachment, at: charIdx, effectiveRange: nil)
            if let chip = attachment as? ImageRefAttachment {
                onTapImage?(chip.imageID)
                return
            }
            if let chip = attachment as? NoteLinkRefAttachment {
                onTapNoteLink?(chip.noteID)
                return
            }
        }
        super.mouseDown(with: event)
    }
}
#endif
