import SwiftUI

struct DayDocumentRow: View {
    let document: Document

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
                .frame(width: 20)

            Text(document.summary ?? "Untitled Document")
                .lineLimit(1)
                .foregroundStyle(document.summary == nil ? .tertiary : .primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
