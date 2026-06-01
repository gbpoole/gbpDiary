import SwiftUI

// Renders the interleaved diary list: root diary tasks and non-task DayEntries
// (notes, meetings). Drop zones between items handle both intra-list reordering
// and drops of foreign UUIDs (meeting tasks, sidebar tasks, etc.).
struct DayEntryListView<RowContent: View>: View {
    let items: [DiaryItem]
    @Binding var activeDropZone: Int?
    let onMoveItem: (DiaryItem, Int) -> Void
    var onDropForeignUUID: ((String, Int) -> Bool)? = nil
    // Return nil to suppress the outer .draggable for an item (e.g. meetings that
    // apply .draggable only to their header card, not the full row).
    var draggableId: ((DiaryItem) -> String?) = { $0.id.uuidString }
    @ViewBuilder var rowContent: (DiaryItem, Int) -> RowContent

    var body: some View {
        if !items.isEmpty {
            itemDropZone(at: 0)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                DraggableRow(content: rowContent(item, index), id: draggableId(item))
                itemDropZone(at: index + 1)
            }
        }
    }

    private func itemDropZone(at index: Int) -> some View {
        ZStack {
            Color.clear.frame(height: 4)
            if activeDropZone == index {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 12)
            }
        }
        .dropDestination(for: String.self) { dropped, _ in
            guard let uuidString = dropped.first,
                  let id = UUID(uuidString: uuidString)
            else { return false }
            if let item = items.first(where: { $0.id == id }) {
                onMoveItem(item, index)
                activeDropZone = nil
                return true
            }
            guard let handler = onDropForeignUUID else { return false }
            let handled = handler(uuidString, index)
            if handled { activeDropZone = nil }
            return handled
        } isTargeted: { targeted in
            activeDropZone = targeted ? index : nil
        }
    }
}

private struct DraggableRow<Content: View>: View {
    let content: Content
    let id: String?

    var body: some View {
        if let id {
            content.draggable(id)
        } else {
            content
        }
    }
}
