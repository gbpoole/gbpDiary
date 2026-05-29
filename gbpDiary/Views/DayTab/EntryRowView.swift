import SwiftUI
import SwiftData
import Textual

struct EntryRowView: View {
    @Bindable var entry: DayEntry
    var focusedEntryId: FocusState<UUID?>.Binding
    var onAddNoteAfter: (() -> Void)? = nil
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil
    var onDeleteEmpty: (() -> Void)? = nil
    var onIndent: (() -> Void)? = nil
    var onOutdent: (() -> Void)? = nil
    var onSelect: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var editingTask: Task?
    @State private var editingMinutes: Minutes?
    @State private var showingDeleteConfirm = false

    private var isEntryFocused: Bool { focusedEntryId.wrappedValue == entry.id }

    private static let indentStep: CGFloat = 20

    var body: some View {
        Group {
            switch entry.kind {
            case .note:    noteRow
            case .task:    taskRow
            case .meeting: meetingRow
            }
        }
        .padding(.leading, CGFloat(entry.indentLevel) * Self.indentStep)
        .alert("Delete Meeting?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let m = entry.minutes { modelContext.delete(m) }
                modelContext.delete(entry)
            }
        } message: {
            Text("This will also delete the associated meeting notes.")
        }
    }

    private func indent() {
        if let handler = onIndent { handler() } else { entry.indentLevel = min(entry.indentLevel + 1, 6) }
    }

    private func outdent() {
        if let handler = onOutdent { handler() } else { entry.indentLevel = max(entry.indentLevel - 1, 0) }
    }

    // MARK: - Visual line helpers (note row only)

    // Inspect the focused NSTextView's layout manager to determine whether the
    // insertion point sits on the topmost or bottommost visual line. Used to
    // decide whether an arrow key should move between entries or stay within
    // the multi-line note text. Defaults to true (navigate between entries) on
    // any platform or state where the check isn't possible.
#if os(macOS)
    private var cursorIsOnFirstVisualLine: Bool {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
              let lm = tv.layoutManager,
              lm.numberOfGlyphs > 0 else { return true }
        let pos = min(tv.selectedRange().location, tv.string.utf16.count)
        let glyph = min(lm.glyphIndexForCharacter(at: pos), lm.numberOfGlyphs - 1)
        let curY = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        let topY = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY
        return curY <= topY + 1
    }

    private var cursorIsOnLastVisualLine: Bool {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
              let lm = tv.layoutManager,
              lm.numberOfGlyphs > 0 else { return true }
        let sel = tv.selectedRange()
        let pos = min(sel.location + sel.length, tv.string.utf16.count)
        let glyph = min(lm.glyphIndexForCharacter(at: pos), lm.numberOfGlyphs - 1)
        let curY = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        let botY = lm.lineFragmentRect(forGlyphAt: lm.numberOfGlyphs - 1, effectiveRange: nil).minY
        return curY >= botY - 1
    }
#endif

    // MARK: - Note

    private var noteRow: some View {
        NoteEntryContent(
            text: $entry.text,
            isFocused: isEntryFocused,
            focusedEntryId: focusedEntryId,
            focusId: entry.id,
            onIndent: indent,
            onOutdent: outdent,
            onMoveToPrevious: onMoveToPrevious,
            onMoveToNext: onMoveToNext,
            allowMoveToPrevious: {
                #if os(macOS)
                return cursorIsOnFirstVisualLine
                #else
                return true
                #endif
            },
            allowMoveToNext: {
                #if os(macOS)
                return cursorIsOnLastVisualLine
                #else
                return true
                #endif
            }
        )
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal)
        .padding(.vertical, 4)
        .contextMenu { deleteButton }
    }

    // MARK: - Task

    private var taskRow: some View {
        rowCard(selectable: true, verticalPadding: 2) {
            TaskEntryContent(
                task: entry.task,
                focusedEntryId: focusedEntryId,
                focusId: entry.id,
                onEdit: { task in editingTask = task },
                onMoveToPrevious: onMoveToPrevious,
                onMoveToNext: onMoveToNext,
                onIndent: onIndent,
                onOutdent: onOutdent
            )
        }
        .contextMenu { deleteButton }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: entry.createdAt)
        }
    }

    // MARK: - Meeting

    private var meetingRow: some View {
        let summaryBinding = Binding<String>(
            get: { entry.inlineSummary },
            set: { entry.inlineSummary = $0 }
        )
        return MeetingEntryContent(
            summaryBinding: summaryBinding,
            minutes: entry.minutes,
            isEntryFocused: isEntryFocused,
            onEdit: { minutes in editingMinutes = minutes },
            inlineText: { binding in
                entryTextView(placeholder: "Meeting summary", text: binding)
            }
        )
        .contextMenu { deleteButton }
        .modifier(RowCardStyling(selectable: true, verticalPadding: 2, onSelect: onSelect))
        .sheet(item: $editingMinutes) { m in MinutesDetailView(minutes: m, asSheet: true) }
    }

    // ZStack text element for meeting rows:
    // Text controls layout width when unfocused; TextField (always present) handles
    // focus machinery and inline editing when focused.
    @ViewBuilder
    private func entryTextView(placeholder: String, text: Binding<String>) -> some View {
        InlineEditableSingleLineText(
            placeholder: placeholder,
            text: text,
            isFocused: isEntryFocused,
            focusBinding: focusedEntryId,
            focusId: entry.id,
            onIndent: indent,
            onOutdent: outdent,
            onMoveToPrevious: onMoveToPrevious,
            onMoveToNext: onMoveToNext
        )
    }

    // MARK: - Shared

    private var deleteButton: some View {
        Button("Delete", role: .destructive) {
            if entry.kind == .meeting && entry.minutes != nil {
                showingDeleteConfirm = true
            } else {
                modelContext.delete(entry)
            }
        }
    }

    private func rowCard<Content: View>(
        selectable: Bool,
        verticalPadding: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .modifier(RowCardStyling(selectable: selectable, verticalPadding: verticalPadding, onSelect: onSelect))
    }
}

private struct NoteEntryContent: View {
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
                .frame(minHeight: 44)
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
                .allowsHitTesting(isFocused)
                .opacity(isFocused ? 1 : 0)

            #if os(macOS)
            if !isFocused {
                NoteViewModeOverlay()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #endif
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { focusedEntryId.wrappedValue = focusId }
    }
}

private struct TaskEntryContent: View {
    let task: Task?
    let focusedEntryId: FocusState<UUID?>.Binding
    let focusId: UUID
    let onEdit: (Task) -> Void
    let onMoveToPrevious: (() -> Void)?
    let onMoveToNext: (() -> Void)?
    let onIndent: (() -> Void)?
    let onOutdent: (() -> Void)?

    var body: some View {
        if let task {
            TaskRowView(
                task: task,
                onEdit: { onEdit(task) },
                inlineEditing: true,
                focusBinding: focusedEntryId,
                focusId: focusId,
                onMoveToPrevious: onMoveToPrevious,
                onMoveToNext: onMoveToNext,
                onIndent: onIndent,
                onOutdent: onOutdent
            )
        } else {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                Text("(missing task)").foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 5)
        }
    }
}

private struct MeetingEntryContent<InlineText: View>: View {
    let summaryBinding: Binding<String>
    let minutes: Minutes?
    let isEntryFocused: Bool
    let onEdit: (Minutes) -> Void
    @ViewBuilder var inlineText: (Binding<String>) -> InlineText

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(.blue)
                .font(.system(size: 17))
                .frame(width: 22, height: 22)
            HStack(alignment: .center, spacing: 6) {
                inlineText(summaryBinding)
                if let minutes {
                    Chip(label: minutes.meetingAt.formatted(.dateTime.hour().minute()), color: .blue)
                    InlineRowEditButton { onEdit(minutes) }
                }
                if !isEntryFocused { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
    }
}

private struct RowCardStyling: ViewModifier {
    let selectable: Bool
    let verticalPadding: CGFloat
    let onSelect: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal)
            .padding(.vertical, verticalPadding)
            .simultaneousGesture(TapGesture().onEnded { _ in
                guard selectable else { return }
                onSelect?()
            })
    }
}

// MARK: - AppKit view-mode overlay

// Present in the ZStack when the note row is unfocused.
// hitTest returns nil so AppKit's mouse dispatch skips this view — mouse events
// fall through to SwiftUI's gesture recognizers, enabling .draggable() and
// .onTapGesture to work normally from anywhere on the row.
// NSDraggingDestination is retained because drag delivery is frame-based (not
// hit-test-based): it swallows UUID string drops, preventing them from landing
// in the hidden TextEditor below.
#if os(macOS)
private struct NoteViewModeOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> NoteViewModeNSView { NoteViewModeNSView() }
    func updateNSView(_ nsView: NoteViewModeNSView, context: Context) {}
}

private final class NoteViewModeNSView: NSView {
    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.string])
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .generic }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
}
#endif
