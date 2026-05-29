import SwiftUI
import Textual

struct MarkdownEditorSection: View {
    @Binding var text: String
    let label: String
    var placeholder: String = "Nothing recorded."
    var minEditorHeight: CGFloat = 120
    var startEditing: Bool = false

    @State private var isEditing: Bool = false

    init(
        text: Binding<String>,
        label: String,
        placeholder: String = "Nothing recorded.",
        minEditorHeight: CGFloat = 120,
        startEditing: Bool = false
    ) {
        self._text = text
        self.label = label
        self.placeholder = placeholder
        self.minEditorHeight = minEditorHeight
        self._isEditing = State(initialValue: startEditing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button { isEditing.toggle() } label: {
                    Image(systemName: isEditing ? "checkmark.circle" : "pencil")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(isEditing ? "Done editing" : "Edit")
            }

            if isEditing {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: minEditorHeight)
            } else if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .font(.body)
            } else {
                StructuredText(markdown: text.replacingOccurrences(of: "\n", with: "  \n"))
                    .textual.textSelection(.enabled)
                    .textual.structuredTextStyle(.gitHub)
                    .font(.body)
            }
        }
    }
}
