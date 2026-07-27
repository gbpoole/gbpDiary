import SwiftUI
import SwiftData

// Edit an already-inserted note-to-note link: repoint it to a different content note (tag-filterable
// picker) or remove it. Opened by clicking a link chip in the source editor.
struct NoteLinkEditSheet: View {
    let currentTargetID: UUID
    let currentTitle: String
    let linkableNotes: [Note]
    var onChangeTarget: (UUID) -> Void
    var onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Note?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Links to").font(.caption).foregroundStyle(.secondary)
                        Text(currentTitle).font(.title3.weight(.semibold))
                    }
                    GroupBox("Change target") {
                        FuzzyPickerField(
                            allItems: linkableNotes,
                            selectedItem: $selected,
                            label: { $0.title.isEmpty ? "Untitled" : $0.title },
                            chipColor: AppTheme.project,
                            placeholder: "Search notes…",
                            tapArea: true,
                            emptyLabel: "Tap to pick a different note",
                            filters: tagFilters.isEmpty ? nil : tagFilters,
                            filterLeadContent: nil
                        )
                    }
                    Button(role: .destructive) { onRemove(); dismiss() } label: {
                        Label("Remove Link", systemImage: "trash")
                    }
                }
                .padding()
            }
            .navigationTitle("Edit Link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let selected, selected.id != currentTargetID { onChangeTarget(selected.id) }
                        dismiss()
                    }
                    .disabled(selected == nil || selected?.id == currentTargetID)
                }
            }
        }
        .onAppear { selected = linkableNotes.first { $0.id == currentTargetID } }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 260)
        #endif
    }

    private var tagFilters: [PickerFilter<Note>] {
        let tags = Set(linkableNotes.flatMap(\.tags)).sorted()
        return tags.map { tag in
            PickerFilter<Note>(id: "tag.\(tag)", label: tag, chipColor: AppTheme.tag, group: "Tag") {
                $0.tags.contains(tag)
            }
        }
    }
}
