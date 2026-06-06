import SwiftUI

struct DayDocumentRow: View {
    let document: Document
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
                .frame(width: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(document.summary ?? "Untitled Document")
                        .lineLimit(1)
                        .foregroundStyle(document.summary == nil ? .tertiary : .primary)
                    if !document.attachments.isEmpty {
                        Chip(label: "\(document.attachments.count) \(document.attachments.count == 1 ? "file" : "files")",
                             color: .gray)
                    }
                    Spacer(minLength: 0)
                    InlineRowEditButton(action: onEdit)
                }
                if let desc = document.documentDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
