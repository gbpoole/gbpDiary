import SwiftUI

struct EntryInlineKeyHandling: ViewModifier {
    let onIndent: (() -> Void)?
    let onOutdent: (() -> Void)?
    let onMoveToPrevious: (() -> Void)?
    let onMoveToNext: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onKeyPress(.tab, phases: .down) { _ in
                if let onIndent {
                    onIndent()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(KeyEquivalent("\u{19}"), phases: .down) { _ in
                if let onOutdent {
                    onOutdent()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.upArrow, phases: .down) { _ in
                if let onMoveToPrevious {
                    onMoveToPrevious()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.downArrow, phases: .down) { _ in
                if let onMoveToNext {
                    onMoveToNext()
                    return .handled
                }
                return .ignored
            }
    }
}

extension View {
    func entryInlineKeyHandling(
        onIndent: (() -> Void)? = nil,
        onOutdent: (() -> Void)? = nil,
        onMoveToPrevious: (() -> Void)? = nil,
        onMoveToNext: (() -> Void)? = nil
    ) -> some View {
        modifier(
            EntryInlineKeyHandling(
                onIndent: onIndent,
                onOutdent: onOutdent,
                onMoveToPrevious: onMoveToPrevious,
                onMoveToNext: onMoveToNext
            )
        )
    }
}
