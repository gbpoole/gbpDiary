import SwiftUI
import SwiftData

struct DayNoteRow: View {
    @Bindable var note: Note
    let focusedEntryId: FocusState<UUID?>.Binding
    var onMoveToPrevious: (() -> Void)? = nil
    var onMoveToNext: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    private var isFocused: Bool { focusedEntryId.wrappedValue == note.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EntryNotesSubArea(
                text: $note.content,
                isFocused: isFocused,
                focusedEntryId: focusedEntryId,
                focusId: note.id,
                placeholder: "Note…",
                onMoveToPrevious: onMoveToPrevious,
                onMoveToNext: onMoveToNext
            )

            HStack(spacing: 4) {
                if let project = note.project {
                    Chip(label: project.name, color: .indigo)
                }
                ForEach(note.tags, id: \.self) { tag in
                    Chip(label: tag, color: .teal)
                }
                Spacer(minLength: 0)
                if let onEdit {
                    InlineRowEditButton(action: onEdit)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .padding(.horizontal)
        .contextMenu {
            Button("Edit…") { onEdit?() }
            Divider()
            Button("Delete", role: .destructive) { onDelete?() }
        }
    }
}
