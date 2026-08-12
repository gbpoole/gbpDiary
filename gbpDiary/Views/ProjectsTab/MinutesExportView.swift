#if os(macOS)
import SwiftUI
import AppKit

// The off-screen SwiftUI page rendered to PDF by MinutesDetailView.exportPDF() via
// NSHostingView.dataWithPDF. Composes the meeting header + Action Items + Documents + the minutes body,
// styled with the selected `ExportPalette`. The body markdown is split into text/image segments: text
// is rendered by `PDFMarkdownView` (NSTextView + NSAttributedString(html:), single CoreText pass — the
// only thing dataWithPDF captures reliably) and images by `PDFImageView` (NSImageView, framed at the
// chosen display width). SwiftUI `Image`/HTML `<img>` don't size/draw correctly into the PDF context.
struct MinutesExportView: View {
    let title: String
    let dateLine: String
    let metaLines: [String]
    let actionItems: [String]
    let documents: [String]
    let bodyMarkdown: String
    let attachments: [Attachment]
    let palette: ExportPalette

    private static let pageWidth: CGFloat = 612
    private static let pageMargin: CGFloat = 20
    private static let cardPadding: CGFloat = 36
    private var contentWidth: CGFloat { Self.pageWidth - (Self.pageMargin + Self.cardPadding) * 2 }

    var body: some View {
        content
            .padding(Self.cardPadding)
            .frame(width: Self.pageWidth - Self.pageMargin * 2, alignment: .leading)
            .background(palette.cardColor, in: RoundedRectangle(cornerRadius: 14))
            .padding(Self.pageMargin)
            .frame(width: Self.pageWidth, alignment: .leading)
            .background(palette.pageColor)
            .environment(\.colorScheme, palette.isLight ? .light : .dark)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            sectionHeader("Action Items")
            if actionItems.isEmpty {
                Text("None.").font(.system(size: 13)).foregroundStyle(palette.mutedTextColor)
            } else {
                bulletList(actionItems)
            }
            if !documents.isEmpty {
                sectionHeader("Documents")
                bulletList(documents)
            }
            Divider().overlay(palette.mutedTextColor.opacity(0.4))
            bodyView
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(palette.accentColor)
            Text(dateLine)
                .font(.system(size: 12))
                .foregroundStyle(palette.mutedTextColor)
            ForEach(metaLines, id: \.self) { line in
                Text(.init(line))   // renders **bold** labels
                    .font(.system(size: 12))
                    .foregroundStyle(palette.mutedTextColor)
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(palette.headingColor(2))
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                    Text(.init(item))
                }
                .font(.system(size: 13))
                .foregroundStyle(palette.bodyTextColor)
            }
        }
    }

    private var bodyView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(NotePDFSegments.segments(from: bodyMarkdown).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let markdown):
                    PDFMarkdownView(html: palette.bodyHTMLDocument(markdown), width: contentWidth)
                        .frame(width: contentWidth, alignment: .leading)
                case .image(let id):
                    if let att = attachments.first(where: { $0.id == id }),
                       let image = NSImage(contentsOf: att.fileURL) {
                        let size = ImageDisplaySize.fit(
                            intrinsic: pixelSize(of: image), proposedWidth: contentWidth,
                            widthFraction: att.displayWidthPercent.map { CGFloat($0) / 100 })
                        // Draw the full-resolution image into the target-sized box so the PDF embeds
                        // full-res pixels (crisp at any zoom) while displaying at `size`.
                        PDFImageView(image: image)
                            .frame(width: size.width, height: size.height)
                    }
                }
            }
        }
    }

    private func pixelSize(of image: NSImage) -> CGSize {
        if let rep = image.representations.first as? NSBitmapImageRep {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }
}

// MARK: - PDF text (NSTextView renders NSAttributedString(html:) in a single CoreText pass)

private struct PDFMarkdownView: NSViewRepresentable {
    let html: String
    let width: CGFloat

    func makeNSView(context: Context) -> AutosizingTextView {
        let tv = AutosizingTextView()
        tv.isEditable = false
        tv.isSelectable = false
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        configure(tv)
        return tv
    }

    func updateNSView(_ tv: AutosizingTextView, context: Context) { configure(tv) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: AutosizingTextView, context: Context) -> CGSize? {
        guard let container = tv.textContainer, let manager = tv.layoutManager else { return nil }
        manager.ensureLayout(for: container)
        return CGSize(width: proposal.width ?? width, height: manager.usedRect(for: container).height)
    }

    private func configure(_ tv: AutosizingTextView) {
        tv.textContainer?.containerSize = CGSize(width: width, height: 1_000_000)
        guard let storage = tv.textStorage else { return }
        if let data = html.data(using: .utf8),
           let attr = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.html,
                         .characterEncoding: String.Encoding.utf8.rawValue],
               documentAttributes: nil) {
            storage.setAttributedString(attr)
        } else {
            storage.setAttributedString(NSAttributedString(string: html))
        }
        tv.invalidateIntrinsicContentSize()
    }
}

private final class AutosizingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let manager = layoutManager else { return super.intrinsicContentSize }
        manager.ensureLayout(for: container)
        return NSSize(width: NSView.noIntrinsicMetric, height: manager.usedRect(for: container).height)
    }
}

// MARK: - PDF image
//
// A custom NSView that draws the **full-resolution** image into its bounds via `NSImage.draw(in:)`.
// SwiftUI `Image` doesn't draw into the PDF `CGContext`, and framing an oversized `NSImageView` down
// doesn't scale it in the `dataWithPDF` pass (it overflows). Drawing into `bounds` both respects the
// SwiftUI frame (no overflow) and embeds the full-res pixels (crisp at any zoom).
private struct PDFImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> PDFImageNSView {
        let view = PDFImageNSView()
        view.image = image
        return view
    }

    func updateNSView(_ view: PDFImageNSView, context: Context) { view.image = image }
}

private final class PDFImageNSView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        image?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }
}
#endif
