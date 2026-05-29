import SwiftUI
import Textual

struct NoteEntryContent: View {
    @Binding var text: String
    let isFocused: Bool
    let focusedEntryId: FocusState<UUID?>.Binding
    let focusId: UUID
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onMoveToPrevious: (() -> Void)?
    let onMoveToNext: (() -> Void)?
    let allowMoveToPrevious: () -> Bool
    let allowMoveToNext: () -> Bool
    var onSplit: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !isFocused {
                if text.isEmpty {
                    Text("Add a note…")
                        .foregroundStyle(.tertiary)
                        .font(.body)
                        .padding(.top, 9)
                        .padding(.leading, 5)
                } else {
                    StructuredText(markdown: text.replacingOccurrences(of: "\n", with: "  \n"))
                        .textual.structuredTextStyle(.gitHub)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .focused(focusedEntryId, equals: focusId)
                .frame(minHeight: isFocused ? 44 : 0, maxHeight: isFocused ? .infinity : 0)
                .scrollDisabled(true)
                .onKeyPress(.tab, phases: .down) { _ in onIndent(); return .handled }
                .onKeyPress(KeyEquivalent("\u{19}"), phases: .down) { _ in onOutdent(); return .handled }
                .onKeyPress(.upArrow, phases: .down) { _ in
                    guard allowMoveToPrevious() else { return .ignored }
                    if let move = onMoveToPrevious { move(); return .handled }
                    return .ignored
                }
                .onKeyPress(.downArrow, phases: .down) { _ in
                    guard allowMoveToNext() else { return .ignored }
                    if let move = onMoveToNext { move(); return .handled }
                    return .ignored
                }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command), let split = onSplit else { return .ignored }
                    split()
                    return .handled
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
    }
}
