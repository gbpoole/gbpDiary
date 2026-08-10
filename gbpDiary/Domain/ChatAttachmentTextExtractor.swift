import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

nonisolated enum ChatAttachmentExtractionFailure: String, Codable, Error, Equatable, Sendable {
    case unsupportedType
    case missingFile
    case fileTooLarge
    case unreadable
    case invalidUTF8
    case pdfUnavailable
    case noText
}

nonisolated struct ChatAttachmentExtraction: Equatable, Sendable {
    let text: String?
    let failure: ChatAttachmentExtractionFailure?

    static func success(_ text: String) -> Self { Self(text: text, failure: nil) }
    static func failed(_ failure: ChatAttachmentExtractionFailure) -> Self { Self(text: nil, failure: failure) }
}

nonisolated struct ChatAttachmentDescriptor: Equatable, Sendable {
    let id: UUID
    let source: ChatSourceReference
    let fileURL: URL
    let fileName: String
    let attachmentDescription: String?
    let isPDF: Bool
    let isText: Bool
    let mimeType: String?
}

nonisolated struct ChatAttachmentTextExtractor: Sendable {
    var maximumBytes = 5_000_000
    var maximumCharacters = 100_000
    var maximumPDFPages = 200

    private static let textExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "csv", "json", "yaml", "yml"
    ]

    func extract(_ attachment: Attachment) -> ChatAttachmentExtraction {
        extract(ChatAttachmentDescriptor(
            id: attachment.id,
            source: ChatSourceReference(id: attachment.id, kind: .attachment,
                                        title: attachment.libraryName, detail: nil,
                                        navigationKind: .attachment, navigationURL: attachment.fileURL),
            fileURL: attachment.fileURL, fileName: attachment.fileName,
            attachmentDescription: attachment.attachmentDescription,
            isPDF: attachment.kind == .pdf || attachment.fileURL.pathExtension.lowercased() == "pdf",
            isText: isText(attachment), mimeType: attachment.mimeType
        ))
    }

    func extract(_ attachment: ChatAttachmentDescriptor) -> ChatAttachmentExtraction {
        let url = attachment.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return .failed(.missingFile) }
        guard fileSize(at: url).map({ $0 <= maximumBytes }) ?? false else { return .failed(.fileTooLarge) }

        if attachment.isPDF {
            return extractPDF(at: url)
        }
        guard attachment.isText else { return .failed(.unsupportedType) }
        do {
            let data = try Data(contentsOf: url)
            guard let value = String(data: data, encoding: .utf8) else { return .failed(.invalidUTF8) }
            return bounded(value)
        } catch {
            return .failed(.unreadable)
        }
    }

    private func isText(_ attachment: Attachment) -> Bool {
        if attachment.kind == .text { return true }
        if Self.textExtensions.contains(attachment.fileURL.pathExtension.lowercased()) { return true }
        guard let mime = attachment.mimeType?.lowercased() else { return false }
        return mime.hasPrefix("text/") || mime == "application/json" || mime == "application/yaml" || mime == "application/x-yaml"
    }

    private func fileSize(at url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }

    private func bounded(_ value: String) -> ChatAttachmentExtraction {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .failed(.noText) }
        return .success(String(normalized.prefix(max(0, maximumCharacters))))
    }

    private func extractPDF(at url: URL) -> ChatAttachmentExtraction {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else { return .failed(.unreadable) }
        let pageCount = min(document.pageCount, max(0, maximumPDFPages))
        let text = (0..<pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
        return bounded(text)
        #else
        return .failed(.pdfUnavailable)
        #endif
    }
}
