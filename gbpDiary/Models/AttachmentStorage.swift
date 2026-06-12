import Foundation
import ImageIO
import CoreGraphics

// Manages the on-disk location for copied attachment files.
//
// All imported files are copied into the app container so they are always accessible
// without security-scoped bookmark resolution, and so the same path works on iOS.
//
// iCloud migration: when the ubiquity container is configured, uncomment the
// `url(forUbiquityContainerIdentifier:)` block below and run a one-time migration
// that moves existing files from the local directory to the iCloud container.
enum AttachmentStorage {

    static var attachmentsDirectory: URL {
        // Future iCloud path — enable when cloudKitContainerIdentifier is added:
        // if let iCloud = FileManager.default.url(forUbiquityContainerIdentifier: nil)?
        //     .appendingPathComponent("Documents/Attachments") {
        //     try? FileManager.default.createDirectory(at: iCloud, withIntermediateDirectories: true)
        //     return iCloud
        // }

        let base: URL
        #if os(macOS)
        base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #else
        base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #endif
        let dir = base.appendingPathComponent("Attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Copies the file at `sourceURL` into the attachments directory.
    // The destination filename is `<fileId>.<ext>` to guarantee uniqueness.
    static func store(from sourceURL: URL, fileId: UUID) throws -> URL {
        let dest = attachmentsDirectory
            .appendingPathComponent(fileId.uuidString)
            .appendingPathExtension(sourceURL.pathExtension)
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return dest
    }

    static func delete(at fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Image processing

    static let sourceMaxWidth = 2048
    static let renderStepWidths = [200, 400, 600, 800, 1000, 1200, 1600, 2048]

    // Returns all renderStepWidths — upscaling beyond sourceWidth is allowed
    static func renderSteps(forSourceWidth sourceWidth: Int) -> [Int] {
        return renderStepWidths
    }

    // Canonical render file URL: {uuid}_r{width}.png in attachmentsDirectory
    static func renderURL(forSourceURL sourceURL: URL, width: Int) -> URL {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        return attachmentsDirectory
            .appendingPathComponent("\(base)_r\(width)")
            .appendingPathExtension("png")
    }

    // Returns pixel width of image at url, or nil if not readable
    static func imagePixelWidth(at url: URL) -> Int? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int else { return nil }
        return w
    }

    // Resizes image at sourceURL to targetWidth, returns PNG data; returns nil on failure
    static func resizedImageData(at sourceURL: URL, targetWidth: Int) -> Data? {
        guard let src = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let srcW = cgImage.width
        let srcH = cgImage.height
        guard srcW > 0 else { return nil }
        let scale = Double(targetWidth) / Double(srcW)
        let targetHeight = max(1, Int(Double(srcH) * scale))
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let resized = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, resized, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // Caps image at url to sourceMaxWidth if wider, writing PNG back in place; returns final source width
    static func capSource(at url: URL) -> Int {
        guard let srcWidth = imagePixelWidth(at: url) else { return 0 }
        guard srcWidth > sourceMaxWidth else { return srcWidth }
        guard let data = resizedImageData(at: url, targetWidth: sourceMaxWidth) else { return srcWidth }
        try? data.write(to: url)
        return sourceMaxWidth
    }
}
