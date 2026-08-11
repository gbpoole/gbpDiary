import SwiftUI
import Textual
import ImageIO

// A Textual image attachment that renders the full-resolution image but clamps its display width to an
// optional per-image maximum (the user's chosen size). Mirrors Textual's built-in image sizing plus the
// max-width clamp; the underlying original file is untouched, so exports/PDF stay full-resolution.
//
// `@unchecked Sendable`: `CGImage` is immutable and safe to read across threads.
struct SizedImageAttachment: Textual.Attachment, @unchecked Sendable {
    let cgImage: CGImage
    let intrinsic: CGSize
    /// Fraction of the available (pane) width to occupy; nil = full width (fit).
    let widthFraction: CGFloat?
    /// The image's file URL string — identity for Hashable and the alt-text fallback.
    let id: String

    var description: String { id }

    static func == (lhs: SizedImageAttachment, rhs: SizedImageAttachment) -> Bool {
        lhs.id == rhs.id && lhs.widthFraction == rhs.widthFraction
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(widthFraction)
    }

    var body: some View {
        SwiftUI.Image(decorative: cgImage, scale: 1.0).resizable()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize {
        ImageDisplaySize.fit(intrinsic: intrinsic, proposedWidth: proposal.width, widthFraction: widthFraction)
    }

    func pngData() -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}

// Loads note images from their local file URLs and applies a per-image max display width (looked up via
// `maxWidth`). Replaces Textual's default image loader for note previews so manual sizing takes effect
// while keeping originals on disk. Remote/animated images aren't used in notes, so a static decode is fine.
struct SizedImageLoader: AttachmentLoader {
    /// Maps a resolved image file URL to its chosen width fraction (0–1), or nil to fit the pane.
    let widthFraction: @Sendable (URL) -> CGFloat?

    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> some Textual.Attachment {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return SizedImageAttachment(
            cgImage: image,
            intrinsic: CGSize(width: image.width, height: image.height),
            widthFraction: widthFraction(url),
            id: url.absoluteString)
    }
}

extension View {
    /// Apply per-image manual sizing to a Textual note preview, using the note's attachments to look up
    /// each image's chosen `displayWidthPercent`. Images without one fit the pane as before.
    func noteImageSizing(_ attachments: [Attachment]) -> some View {
        // Snapshot a Sendable [urlString: fraction] map so the loader closure stays Sendable.
        let fractions: [String: CGFloat] = attachments.reduce(into: [:]) { map, att in
            if let percent = att.displayWidthPercent {
                map[att.fileURL.absoluteString] = CGFloat(percent) / 100
            }
        }
        return self.textual.imageAttachmentLoader(
            SizedImageLoader(widthFraction: { url in fractions[url.absoluteString] })
        )
    }
}
