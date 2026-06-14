import SwiftUI


struct InlineEditableSingleLineText: View {
    let placeholder: String
    @Binding var text: String
    var isFocused: Bool
    var focusBinding: FocusState<UUID?>.Binding
    var focusId: UUID
    var struckThrough: Bool = false
    var foregroundColor: Color = .primary
    var onIndent: (() -> Void)? = nil
    var onOutdent: (() -> Void)? = nil
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil

    @State private var draft: String = ""
    @State private var debouncer = Debouncer()

    var body: some View {
        ZStack(alignment: .leading) {
            Text(draft.isEmpty ? " " : draft)
                .lineLimit(1)
                .strikethrough(struckThrough)
                .foregroundStyle(foregroundColor)
                .opacity(isFocused ? 0 : 1)

            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .focused(focusBinding, equals: focusId)
                .strikethrough(struckThrough)
                .foregroundStyle(foregroundColor)
                .frame(maxWidth: isFocused ? .infinity : 0)
                .clipped()
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(isFocused)
                .entryInlineKeyHandling(
                    onIndent: onIndent,
                    onOutdent: onOutdent,
                    onMoveToPrevious: onMoveToPrevious,
                    onMoveToNext: onMoveToNext
                )
        }
        .frame(maxWidth: isFocused ? .infinity : nil)
        .contentShape(Rectangle())
        .onTapGesture { focusBinding.wrappedValue = focusId }
        .onAppear { draft = text }
        .onChange(of: draft) { _, newValue in
            debouncer.schedule(delay: 2.0) { text = newValue }
        }
        .onChange(of: isFocused) { _, focused in
            debouncer.cancel()
            if focused { draft = text } else { text = draft }
        }
        .onDisappear { debouncer.cancel(); text = draft }
    }
}
