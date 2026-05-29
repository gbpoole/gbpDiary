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
        ZStack(alignment: .topLeading) {
            if !isEntryFocused {
                if entry.text.isEmpty {
                    Text("Add a note…")
                        .foregroundStyle(.tertiary)
                        .font(.body)
                        .padding(.top, 9)
                        .padding(.leading, 5)
                } else {
                    // StructuredText renders full Markdown (bullets, headings, code blocks).
                    // Two trailing spaces before \n produce CommonMark hard line breaks,
                    // preserving single-newline separation as the user typed it.
                    StructuredText(markdown: entry.text.replacingOccurrences(of: "\n", with: "  \n"))
                        .textual.structuredTextStyle(.gitHub)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            TextEditor(text: $entry.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .focused(focusedEntryId, equals: entry.id)
                .frame(minHeight: 44)
                .scrollDisabled(true)
                .onKeyPress(.tab, phases: .down) { _ in indent(); return .handled }
                .onKeyPress(KeyEquivalent("\u{19}"), phases: .down) { _ in outdent(); return .handled }
                .onKeyPress(.upArrow, phases: .down) { _ in
                    #if os(macOS)
                    guard cursorIsOnFirstVisualLine else { return .ignored }
                    #endif
                    if let move = onMoveToPrevious { move(); return .handled }
                    return .ignored
                }
                .onKeyPress(.downArrow, phases: .down) { _ in
                    #if os(macOS)
                    guard cursorIsOnLastVisualLine else { return .ignored }
                    #endif
                    if let move = onMoveToNext { move(); return .handled }
                    return .ignored
                }
                .allowsHitTesting(isEntryFocused)
                .opacity(isEntryFocused ? 1 : 0)

            // NoteViewModeOverlay sits above the ZStack when unfocused. Its hitTest
            // returns nil so mouse events fall through to SwiftUI's gesture layer
            // (enabling .draggable() and .onTapGesture to work normally). It exists
            // solely to swallow UUID drag-drops that would otherwise land in the
            // hidden TextEditor (NSDraggingDestination is frame-based, not hit-test-based).
            #if os(macOS)
            if !isEntryFocused {
                NoteViewModeOverlay()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #endif
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { focusedEntryId.wrappedValue = entry.id }  // handles empty-note tap
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal)
        .padding(.vertical, 4)
        .contextMenu { deleteButton }
    }

    // MARK: - Task

    private var taskRow: some View {
        Group {
            if let task = entry.task {
                TaskRowView(
                    task: task,
                    onEdit: { editingTask = task },
                    inlineEditing: true,
                    focusBinding: focusedEntryId,
                    focusId: entry.id,
                    onMoveToPrevious: onMoveToPrevious,
                    onMoveToNext: onMoveToNext,
                    onIndent: onIndent,
                    onOutdent: onOutdent
                )
                .simultaneousGesture(TapGesture().onEnded { _ in onSelect?() })
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                    Text("(missing task)").foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.vertical, 5)
                .contextMenu { deleteButton }
            }
        }
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal)
        .padding(.vertical, 2)
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
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(.blue)
                .font(.system(size: 17))
                .frame(width: 22, height: 22)
            HStack(alignment: .center, spacing: 6) {
                entryTextView(placeholder: "Meeting summary", text: summaryBinding)
                if let m = entry.minutes {
                    Chip(label: m.meetingAt.formatted(.dateTime.hour().minute()), color: .blue)
                    Button {
                        editingMinutes = m
                    } label: {
                        Image(systemName: "pencil").foregroundStyle(.tertiary).font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                if !isEntryFocused { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .simultaneousGesture(TapGesture().onEnded { _ in onSelect?() })
        .contextMenu { deleteButton }
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal)
        .padding(.vertical, 2)
        .sheet(item: $editingMinutes) { m in MinutesDetailView(minutes: m, asSheet: true) }
    }

    // ZStack text element for meeting rows:
    // Text controls layout width when unfocused; TextField (always present) handles
    // focus machinery and inline editing when focused.
    @ViewBuilder
    private func entryTextView(placeholder: String, text: Binding<String>) -> some View {
        ZStack(alignment: .leading) {
            Text(text.wrappedValue.isEmpty ? " " : text.wrappedValue)
                .lineLimit(1)
                .opacity(isEntryFocused ? 0 : 1)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .focused(focusedEntryId, equals: entry.id)
                .frame(maxWidth: isEntryFocused ? .infinity : 0)
                .clipped()
                .opacity(isEntryFocused ? 1 : 0)
                .allowsHitTesting(isEntryFocused)
                .onKeyPress(.tab, phases: .down) { _ in indent(); return .handled }
                .onKeyPress(KeyEquivalent("\u{19}"), phases: .down) { _ in outdent(); return .handled }
                .onKeyPress(.upArrow, phases: .down) { _ in
                    if let move = onMoveToPrevious { move(); return .handled }
                    return .ignored
                }
                .onKeyPress(.downArrow, phases: .down) { _ in
                    if let move = onMoveToNext { move(); return .handled }
                    return .ignored
                }
        }
        .frame(maxWidth: isEntryFocused ? .infinity : nil)
        .contentShape(Rectangle())
        .onTapGesture { focusedEntryId.wrappedValue = entry.id }
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
