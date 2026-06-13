import SwiftUI
import Textual

// Tracks tap-related flags that must be visible immediately across closures in the same event
// cycle. Stored as a class so mutations are visible without waiting for a SwiftUI @State render
// cycle — @State changes are batched and may not be committed until after a gesture closure
// has already read the value.
private final class TapFlags {
    var didTapLink = false
}

private final class Debouncer {
    private var work: DispatchWorkItem?
    func schedule(delay: Double, action: @escaping () -> Void) {
        work?.cancel()
        let item = DispatchWorkItem(block: action)
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
    func cancel() { work?.cancel(); work = nil }
}

enum CursorPlacement { case start, end }

struct EntryNotesSubArea: View {
    @Binding var text: String
    let isFocused: Bool
    let focusedEntryId: FocusState<UUID?>.Binding
    let focusId: UUID
    let placeholder: String
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil
    var onSingleTap: (() -> Void)? = nil
    var wasSelectedBeforeTap: (() -> Bool)? = nil
    var isSelected: Bool = false
    var topRounded: Bool = true
    var bottomRounded: Bool = true
    var cursorPlacement: CursorPlacement? = nil
    var onCursorPlacementConsumed: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL
    @State private var tapFlags = TapFlags()
    @State private var tapRequestCount = 0
    @State private var draft: String = ""
    @State private var debouncer = Debouncer()

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 2)
                .padding(.top, topRounded ? 2 : 0)
                .padding(.bottom, bottomRounded ? 2 : 0)

            ZStack(alignment: .topLeading) {
                // Show rendered markdown only when neither selected nor focused.
                // When selected the NSTextView is shown instead (see below) so that
                // the user's second click lands on the actual editing view — AppKit's
                // mouseDown then places the cursor at the click position natively,
                // with no coordinate-space translation needed between renderers.
                if !isFocused && !isSelected {
                    if draft.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .font(.body)
                            .padding(.top, 9)
                            .padding(.leading, 9)
                    } else {
                        StructuredText(
                            markdown: draft.replacingOccurrences(of: "\n", with: "  \n"),
                            syntaxExtensions: [.math]
                        )
                        .textual.structuredTextStyle(.gitHub)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.leading, 6)
                            .padding(.vertical, 6)
                            .environment(\.openURL, OpenURLAction { url in
                                tapFlags.didTapLink = true
                                openURL(url)
                                return .handled
                            })
                    }
                }

                #if os(macOS)
                // NoteTextEditor wraps NSTextView directly.
                // .focused() must be kept so SwiftUI registers a claimant for focusId;
                // without it, setting focusedEntryId.wrappedValue = focusId is
                // immediately reset by SwiftUI because no view owns that focus value.
                // Visible and hit-testable when isSelected so FocusClearMonitor's guard
                // (!(hit is NSTextView)) fails and AppKit routes the click to this view,
                // letting mouseDown place the cursor at the exact click position.
                NoteTextEditor(
                    text: $draft,
                    onMoveToPrevious: onMoveToPrevious,
                    onMoveToNext: onMoveToNext,
                    cursorPlacement: cursorPlacement,
                    onCursorPlacementConsumed: onCursorPlacementConsumed
                )
                .focused(focusedEntryId, equals: focusId)
                .padding(.leading, 4)
                .frame(minHeight: (isFocused || isSelected) ? 44 : 0,
                       maxHeight: (isFocused || isSelected) ? .infinity : 0)
                .allowsHitTesting(isFocused || isSelected)
                .opacity(isFocused || isSelected ? 1 : 0)
                #else
                TextEditor(text: $draft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused(focusedEntryId, equals: focusId)
                    .frame(minHeight: isFocused ? 44 : 0, maxHeight: isFocused ? .infinity : 0)
                    .scrollDisabled(true)
                    .padding(.leading, 4)
                    .onKeyPress(.upArrow, phases: .down) { _ in
                        guard let move = onMoveToPrevious else { return .ignored }
                        move(); return .handled
                    }
                    .onKeyPress(.downArrow, phases: .down) { _ in
                        guard let move = onMoveToNext else { return .ignored }
                        move(); return .handled
                    }
                    .allowsHitTesting(isFocused)
                    .opacity(isFocused ? 1 : 0)
                #endif
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { tapRequestCount += 1 })
            .onChange(of: tapRequestCount) {
                if tapFlags.didTapLink {
                    tapFlags.didTapLink = false
                } else if isFocused {
                    // Already editing — cursor already placed by AppKit or user
                    ()
                } else if wasSelectedBeforeTap?() == true {
                    // Click landed on the 2px border strip (outside NSTextView) while selected.
                    // FocusClearMonitor fired (hit was not NSTextView) so we enter edit mode
                    // manually; cursor goes to end as a fallback.
                    focusedEntryId.wrappedValue = focusId
                } else if let tap = onSingleTap {
                    // First click → select the block
                    tap()
                } else {
                    // No selection model (non-note contexts) → focus immediately
                    focusedEntryId.wrappedValue = focusId
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .onAppear { draft = text }
        .onChange(of: draft) { _, newValue in
            debouncer.schedule(delay: 2.0) { text = newValue }
        }
        .onChange(of: isFocused) { _, focused in
            debouncer.cancel()
            if focused { draft = text } else { text = draft }
        }
        .onDisappear { debouncer.cancel(); text = draft }
        .background(
            Color.secondary.opacity(0.06),
            in: UnevenRoundedRectangle(
                topLeadingRadius:    topRounded    ? 6 : 0,
                bottomLeadingRadius: bottomRounded ? 6 : 0,
                bottomTrailingRadius: bottomRounded ? 6 : 0,
                topTrailingRadius:   topRounded    ? 6 : 0
            )
        )
        .overlay {
            if isSelected && !isFocused {
                UnevenRoundedRectangle(
                    topLeadingRadius:    topRounded    ? 6 : 0,
                    bottomLeadingRadius: bottomRounded ? 6 : 0,
                    bottomTrailingRadius: bottomRounded ? 6 : 0,
                    topTrailingRadius:   topRounded    ? 6 : 0
                )
                .stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }
}

// MARK: - macOS custom text editor

#if os(macOS)

// NSTextView subclass that restores cursor position when gaining focus.
// `pendingPlacement` is set by `updateNSView` before focus transfers;
// `savedRange` is updated on every selection change via the delegate.
private final class ManagedTextView: NSTextView {
    var pendingPlacement: CursorPlacement? = nil
    var savedRange: NSRange? = nil

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            if let p = pendingPlacement {
                switch p {
                case .start: setSelectedRange(NSRange(location: 0, length: 0))
                case .end:   setSelectedRange(NSRange(location: string.utf16.count, length: 0))
                }
                pendingPlacement = nil
            } else if let r = savedRange, r.location + r.length <= string.utf16.count {
                setSelectedRange(r)
            }
        }
        return ok
    }
}

// NSViewRepresentable wrapping NSTextView.
// Handles bidirectional text sync, up/down navigation, and cursor save/restore.
// Focus is driven by SwiftUI via the .focused() modifier applied at the call site.
// Cursor placement when entering edit mode from the selected state is handled natively
// by AppKit's mouseDown(with:) — this view is visible and hit-testable when isSelected,
// so the click reaches it directly and characterIndex(for:) runs on the correct layout.
private struct NoteTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil
    var cursorPlacement: CursorPlacement? = nil
    var onCursorPlacementConsumed: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ManagedTextView {
        let tv = ManagedTextView()
        tv.delegate = context.coordinator
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.drawsBackground = false
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = .zero
        tv.font = .preferredFont(forTextStyle: .body)
        context.coordinator.textView = tv
        return tv
    }

    func updateNSView(_ tv: ManagedTextView, context: Context) {
        if tv.string != text { tv.string = text }
        if let placement = cursorPlacement {
            tv.pendingPlacement = placement
            onCursorPlacementConsumed?()
        }
        context.coordinator.parent = self
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: ManagedTextView, context: Context) -> CGSize? {
        guard let container = tv.textContainer, let manager = tv.layoutManager else { return nil }
        let width = proposal.width ?? 300
        let saved = container.containerSize
        container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let height = max(manager.usedRect(for: container).height, 44)
        container.containerSize = saved
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextEditor
        weak var textView: ManagedTextView?

        init(_ parent: NoteTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, parent.text != tv.string else { return }
            parent.text = tv.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            tv.savedRange = tv.selectedRange()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSTextView.moveUp(_:)):
                if let move = parent.onMoveToPrevious, isOnFirstVisualLine(textView) {
                    move(); return true
                }
            case #selector(NSTextView.moveDown(_:)):
                if let move = parent.onMoveToNext, isOnLastVisualLine(textView) {
                    move(); return true
                }
            default: break
            }
            return false
        }

        private func isOnFirstVisualLine(_ tv: NSTextView) -> Bool {
            guard let lm = tv.layoutManager, lm.numberOfGlyphs > 0 else { return true }
            let pos = min(tv.selectedRange().location, tv.string.utf16.count)
            let glyph = min(lm.glyphIndexForCharacter(at: pos), lm.numberOfGlyphs - 1)
            let curY = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
            let topY = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY
            return curY <= topY + 1
        }

        private func isOnLastVisualLine(_ tv: NSTextView) -> Bool {
            guard let lm = tv.layoutManager, lm.numberOfGlyphs > 0 else { return true }
            let sel = tv.selectedRange()
            let pos = min(sel.location + sel.length, tv.string.utf16.count)
            let glyph = min(lm.glyphIndexForCharacter(at: pos), lm.numberOfGlyphs - 1)
            let curY = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
            let botY = lm.lineFragmentRect(forGlyphAt: lm.numberOfGlyphs - 1, effectiveRange: nil).minY
            return curY >= botY - 1
        }
    }
}

#endif
