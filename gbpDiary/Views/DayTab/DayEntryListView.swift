import SwiftUI

struct DayEntryListView<RowContent: View>: View {
    let entries: [DayEntry]
    @Binding var activeDropZone: Int?
    let onMoveEntry: (DayEntry, Int) -> Void
    @ViewBuilder var rowContent: (DayEntry, Int) -> RowContent

    var body: some View {
        if !entries.isEmpty {
            entryDropZone(at: 0)
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                rowContent(entry, index)
                    .draggable(entry.id.uuidString)
                entryDropZone(at: index + 1)
            }
        }
    }

    private func entryDropZone(at index: Int) -> some View {
        ZStack {
            Color.clear.frame(height: 4)
            if activeDropZone == index {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .padding(.horizontal, 12)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let uuidString = items.first,
                  let id = UUID(uuidString: uuidString),
                  let dragged = entries.first(where: { $0.id == id })
            else { return false }
            onMoveEntry(dragged, index)
            activeDropZone = nil
            return true
        } isTargeted: { targeted in
            activeDropZone = targeted ? index : nil
        }
    }
}
