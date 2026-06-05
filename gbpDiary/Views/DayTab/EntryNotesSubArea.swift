import SwiftUI
import Textual

// Tracks whether a link tap just occurred so the simultaneous edit-mode gesture can be suppressed.
// Stored as a class so mutations in the openURL closure are visible immediately to the
// simultaneously-firing TapGesture closure (value-type @State would queue a re-render, not
// propagate synchronously across two closures in the same event cycle).
private final class LinkTapFlags {
    var didTapLink = false
}

struct EntryNotesSubArea: View {
    @Binding var text: String
    let isFocused: Bool
    let focusedEntryId: FocusState<UUID?>.Binding
    let focusId: UUID
    let placeholder: String
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL
    @State private var linkFlags = LinkTapFlags()

#if os(macOS)
    private var cursorIsOnFirstVisualLine: Bool {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
              let lm = tv.layoutManager, lm.numberOfGlyphs > 0 else { return true }
        let pos = min(tv.selectedRange().location, tv.string.utf16.count)
        let glyph = min(lm.glyphIndexForCharacter(at: pos), lm.numberOfGlyphs - 1)
        let curY = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        let topY = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY
        return curY <= topY + 1
    }

    private var cursorIsOnLastVisualLine: Bool {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
              let lm = tv.layoutManager, lm.numberOfGlyphs > 0 else { return true }
        let sel = tv.selectedRange()
        let pos = min(sel.location + sel.length, tv.string.utf16.count)
        let glyph = min(lm.glyphIndexForCharacter(at: pos), lm.numberOfGlyphs - 1)
        let curY = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        let botY = lm.lineFragmentRect(forGlyphAt: lm.numberOfGlyphs - 1, effectiveRange: nil).minY
        return curY >= botY - 1
    }
#endif

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
                        StructuredText(
                            markdown: text.replacingOccurrences(of: "\n", with: "  \n"),
                            syntaxExtensions: [.math]
                        )
                        .textual.structuredTextStyle(.gitHub)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.leading, 6)
                            .padding(.vertical, 6)
                            .environment(\.openURL, OpenURLAction { url in
                                linkFlags.didTapLink = true
                                openURL(url)
                                return .handled
                            })
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
                        guard let move = onMoveToPrevious else { return .ignored }
                        #if os(macOS)
                        guard cursorIsOnFirstVisualLine else { return .ignored }
                        #endif
                        move(); return .handled
                    }
                    .onKeyPress(.downArrow, phases: .down) { _ in
                        guard let move = onMoveToNext else { return .ignored }
                        #if os(macOS)
                        guard cursorIsOnLastVisualLine else { return .ignored }
                        #endif
                        move(); return .handled
                    }
                    .allowsHitTesting(isFocused)
                    .opacity(isFocused ? 1 : 0)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    if linkFlags.didTapLink {
                        linkFlags.didTapLink = false
                    } else {
                        focusedEntryId.wrappedValue = focusId
                    }
                }
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}
