import Foundation
import SwiftUI
import AppKit
import Testing
@testable import gbpDiary

@MainActor
struct MinutesExportRenderTests {
    private func makePNG(width: Int, height: Int, at url: URL) throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    @Test func exportView_dataWithPDF_producesValidPdfWithImage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let png = dir.appendingPathComponent("pic.png")
        try makePNG(width: 200, height: 120, at: png)

        let att = gbpDiary.Attachment(fileName: "pic.png", fileURL: png, kind: .image)
        att.displayWidthPercent = 50
        let body = "# Heading\n\nSome **bold** text.\n\n\(AttachmentRef.markdown(for: att.id, displayName: "pic"))\n\n- one\n- two"

        let view = MinutesExportView(
            title: "Weekly Sync", dateLine: "today", metaLines: ["**Projects:** X"],
            actionItems: ["Do it — Me"], documents: [], bodyMarkdown: body,
            attachments: [att], palette: .lightShaded)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = .zero
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        #expect(hosting.bounds.width > 0 && hosting.bounds.height > 0)

        let data = hosting.dataWithPDF(inside: hosting.bounds)
        #expect(data.prefix(5) == Data("%PDF-".utf8))
        #expect(data.count > 1000)
    }
}
