import SwiftUI
import Textual

struct EntryNotesSubArea: View {
    @Binding var text: String
    let isFocused: Bool
    let focusedEntryId: FocusState<UUID?>.Binding
    let focusId: UUID
    let placeholder: String
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 2)
                .padding(.vertical, 2)

            ZStack(alignment: .topLeading) {
                if !isFocused {
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .font(.body)
                            .padding(.top, 9)
                            .padding(.leading, 9)
                    } else {
                        StructuredText(markdown: text.replacingOccurrences(of: "\n", with: "  \n"))
                            .textual.structuredTextStyle(.gitHub)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.leading, 6)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }

                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused(focusedEntryId, equals: focusId)
                    .frame(minHeight: isFocused ? 44 : 0, maxHeight: isFocused ? .infinity : 0)
                    .scrollDisabled(true)
                    .padding(.leading, 4)
                    .onKeyPress(.upArrow, phases: .down) { _ in
                        if let move = onMoveToPrevious { move(); return .handled }
                        return .ignored
                    }
                    .onKeyPress(.downArrow, phases: .down) { _ in
                        if let move = onMoveToNext { move(); return .handled }
                        return .ignored
                    }
                    .allowsHitTesting(isFocused)
                    .opacity(isFocused ? 1 : 0)
            }
            #if os(macOS)
            .overlay {
                if !isFocused { NoteViewModeOverlay() }
            }
            #endif
            .contentShape(Rectangle())
            .onTapGesture { focusedEntryId.wrappedValue = focusId }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}
