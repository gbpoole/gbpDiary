import SwiftUI
import Textual

struct MarkdownEditorSection: View {
    @Binding var text: String
    let label: String
    var showHeader: Bool = true
    var placeholder: String = "Nothing recorded."
    var minEditorHeight: CGFloat = 120
    var startEditing: Bool = false

    @State private var isEditing: Bool = false
    @FocusState private var textFocused: Bool

    init(
        text: Binding<String>,
        label: String,
        showHeader: Bool = true,
        placeholder: String = "Nothing recorded.",
        minEditorHeight: CGFloat = 120,
        startEditing: Bool = false
    ) {
        self._text = text
        self.label = label
        self.showHeader = showHeader
        self.placeholder = placeholder
        self.minEditorHeight = minEditorHeight
        self._isEditing = State(initialValue: startEditing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: showHeader ? 8 : 0) {
            if showHeader {
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
            }

            if isEditing {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: minEditorHeight)
                    .scrollContentBackground(.hidden)
                    .focused($textFocused)
                    .onAppear { textFocused = true }
                    .onChange(of: textFocused) { _, focused in
                        if !focused && !showHeader { isEditing = false }
                    }
            } else if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if !showHeader { isEditing = true } }
            } else {
                StructuredText(
                    markdown: text.replacingOccurrences(of: "\n", with: "  \n"),
                    syntaxExtensions: [.math]
                )
                .textual.textSelection(.enabled)
                .textual.structuredTextStyle(.gitHub)
                    .font(.body)
                    .contentShape(Rectangle())
                    .onTapGesture { if !showHeader { isEditing = true } }
            }
        }
    }
}
