import SwiftUI

#if os(macOS)
import AppKit
import ImageIO
import UniformTypeIdentifiers

extension NSPasteboard {
    // PNG data for a pasted/dropped raw image (e.g. a screenshot), or nil if none.
    func imagePNGData() -> Data? {
        guard let image = NSImage(pasteboard: self),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return png
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

    static let minHeight: CGFloat = 120

    private static let refRegex = try! NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\(attachment://([0-9A-Fa-f-]{36})\)"#
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
        tv.onTapImage = onTapImage
        tv.onInsertImageFiles = onInsertImageFiles
        tv.onInsertImageData = onInsertImageData
        tv.onWidthChange = { [weak coordinator = context.coordinator] in coordinator?.scheduleHeightPush() }
        context.coordinator.textView = tv
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
        tv.onInsertImageFiles = onInsertImageFiles
        tv.onInsertImageData = onInsertImageData
        // Only rebuild on an external text change or an explicit refresh — never while the user is
        // typing (textDidChange keeps lastMarkdown in sync so this comparison is false then).
        if text != context.coordinator.lastMarkdown || refreshToken != context.coordinator.lastRefresh {
            context.coordinator.lastRefresh = refreshToken
            context.coordinator.apply(markdown: text, into: tv)
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
        private var heightPushScheduled = false

        init(_ parent: ImageChipTextEditor) { self.parent = parent }

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

        // Build an attributed string from markdown, swapping image refs for chip attachments.
        func apply(markdown: String, into tv: ChipTextView) {
            let attr = NSMutableAttributedString()
            let ns = markdown as NSString
            var cursor = 0
            let matches = ImageChipTextEditor.refRegex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
            for match in matches {
                if match.range.location > cursor {
                    let sub = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                    attr.append(NSAttributedString(string: sub, attributes: ImageChipTextEditor.textAttributes))
                }
                let altText = ns.substring(with: match.range(at: 1))
                let idString = ns.substring(with: match.range(at: 2))
                if let id = UUID(uuidString: idString) {
                    let attachment = parent.attachments.first { $0.id == id }
                    let name = attachment?.displayName ?? attachment?.fileName ?? altText
                    let chip = ImageRefAttachment(imageID: id, displayName: name,
                                                  image: Self.chipImage(for: attachment, name: name))
                    let chipString = NSMutableAttributedString(attachment: chip)
                    // Carry the editor's font/color on the attachment character so text typed right
                    // after a chip inherits the monospace font and label color (not the defaults).
                    chipString.addAttributes(ImageChipTextEditor.textAttributes,
                                             range: NSRange(location: 0, length: chipString.length))
                    attr.append(chipString)
                } else {
                    attr.append(NSAttributedString(string: ns.substring(with: match.range), attributes: ImageChipTextEditor.textAttributes))
                }
                cursor = match.range.location + match.range.length
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

        // Serialize the attributed string back to markdown: chips become their ref, text stays text.
        func serialize(_ storage: NSAttributedString) -> String {
            var out = ""
            let full = NSRange(location: 0, length: storage.length)
            storage.enumerateAttribute(.attachment, in: full) { value, range, _ in
                if let chip = value as? ImageRefAttachment {
                    out += AttachmentRef.markdown(for: chip.imageID, displayName: chip.displayName)
                } else {
                    out += storage.attributedSubstring(from: range).string
                }
            }
            return out
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let markdown = serialize(storage)
            lastMarkdown = markdown
            // Push to SwiftUI on the next run-loop tick. Mutating SwiftUI state synchronously here
            // (mid text-edit) makes SwiftUI re-run sizeThatFits/ensureLayout re-entrantly on the text
            // view being edited, which storms the layout system and beach-balls. Deferring lets
            // AppKit finish its edit cycle first.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.text != markdown { self.parent.text = markdown }
                self.pushHeight()
            }
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
    }
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
    var onWidthChange: (() -> Void)?
    var onInsertImageFiles: (([URL], Int) -> Void)?
    var onInsertImageData: ((Data, Int) -> Void)?
    private var lastWidth: CGFloat = 0

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if abs(newSize.width - lastWidth) > 0.5 {
            lastWidth = newSize.width
            onWidthChange?()   // content reflows at the new width → re-measure height
        }
    }

    // MARK: - Image paste

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let index = selectedRange().location
        if let urls = ChipTextView.imageFileURLs(from: pb), !urls.isEmpty {
            onInsertImageFiles?(urls, index); return
        }
        if let data = pb.imagePNGData() {
            onInsertImageData?(data, index); return
        }
        super.paste(sender)
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
        let index = characterIndexForInsertion(at: point)
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
        if charIdx < ts.length,
           let chip = ts.attribute(.attachment, at: charIdx, effectiveRange: nil) as? ImageRefAttachment {
            onTapImage?(chip.imageID)
            return
        }
        super.mouseDown(with: event)
    }
}
#endif
