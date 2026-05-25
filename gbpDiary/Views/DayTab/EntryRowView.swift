import SwiftUI
import SwiftData

struct EntryRowView: View {
    @Bindable var entry: DayEntry
    var focusedEntryId: FocusState<UUID?>.Binding
    var onAddNoteAfter: (() -> Void)? = nil
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil
    var onDeleteEmpty: (() -> Void)? = nil
    var onIndent: (() -> Void)? = nil
    var onOutdent: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var editingTask: Task?
    @State private var showingEditMeeting = false

    private static let indentStep: CGFloat = 20

    var body: some View {
        Group {
            switch entry.kind {
            case .note:      noteRow
            case .task:      taskRow
            case .meeting:   meetingRow
            case .timesheet: timesheetRow
            }
        }
        .padding(.leading, CGFloat(entry.indentLevel) * Self.indentStep)
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
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
            TextField("", text: $entry.text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused(focusedEntryId, equals: entry.id)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        entry.text += "\n"
                        return .handled
                    }
                    onAddNoteAfter?()
                    return .handled
                }
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
        }
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
                    onMoveToNext: onMoveToNext
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
                .contextMenu { deleteButton }
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorSheet(task: task, defaultDate: entry.createdAt)
        }
    }

    // MARK: - Meeting

    private var meetingRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(.blue)
                .frame(width: 22, height: 22)
            if let m = entry.minutes {
                Text(m.summary ?? m.meetingAt.formatted(.dateTime.hour().minute().day().month()))
            } else {
                TextField("Meeting description", text: $entry.text)
                    .textFieldStyle(.plain)
                    .focused(focusedEntryId, equals: entry.id)
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
            Button { showingEditMeeting = true } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .contextMenu { deleteButton }
        .sheet(isPresented: $showingEditMeeting) {
            MeetingEntryEditorSheet(entry: entry)
        }
    }

    // MARK: - Timesheet

    private var timesheetRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "clock")
                .foregroundStyle(.orange)
                .frame(width: 22, height: 22)
            TextField("Description", text: $entry.text)
                .textFieldStyle(.plain)
                .focused(focusedEntryId, equals: entry.id)
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
            if let dur = entry.duration {
                Chip(label: dur.displayString, color: .orange)
            }
            if let proj = entry.project {
                Chip(label: proj.name, color: .blue)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .contextMenu { deleteButton }
    }

    // MARK: - Shared

    private var deleteButton: some View {
        Button("Delete", role: .destructive) {
            modelContext.delete(entry)
        }
    }
}

private struct MeetingEntryEditorSheet: View {
    @Bindable var entry: DayEntry
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Description") {
                    TextField("Meeting description", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                }
                if let m = entry.minutes {
                    Section("Linked Meeting") {
                        LabeledContent("Time") {
                            Text(m.meetingAt, format: .dateTime.weekday(.wide).hour().minute())
                        }
                        if let summary = m.summary, !summary.isEmpty {
                            LabeledContent("Summary") { Text(summary) }
                        }
                    }
                }
            }
            .navigationTitle("Edit Meeting")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { entry.text = text; dismiss() }
                }
            }
        }
        .onAppear { text = entry.text }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 220)
        #endif
    }
}
