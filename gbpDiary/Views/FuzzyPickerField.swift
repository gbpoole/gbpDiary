import SwiftUI

/// A reusable search-filter selector with chips for selected items.
///
/// Embeds a live-filtered list inside any form or sheet context.
/// Supports multi-select (default) and single-select (`maxSelections: 1`).
/// An optional sticky "+ Create…" row calls `onCreate` when tapped.
struct FuzzyPickerField<Item: Identifiable>: View {
    let allItems: [Item]
    @Binding var selected: [Item]
    let label: (Item) -> String
    let chipColor: Color
    var placeholder: String = "Search…"
    var maxSelections: Int = Int.max
    var createLabel: String? = nil
    var onCreate: (() -> Void)? = nil

    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    private var filteredItems: [Item] {
        guard !searchText.isEmpty else { return allItems }
        let q = searchText.lowercased()
        return allItems.filter { label($0).lowercased().contains(q) }
    }

    private func isSelected(_ item: Item) -> Bool {
        selected.contains(where: { $0.id == item.id })
    }

    private func toggle(_ item: Item) {
        if isSelected(item) {
            selected.removeAll { $0.id == item.id }
        } else {
            if maxSelections == 1 {
                selected = [item]
                searchText = ""
            } else if selected.count < maxSelections {
                selected.append(item)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !selected.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(selected) { item in
                        PickerRemovableChip(label: label(item), color: chipColor) {
                            selected.removeAll { $0.id == item.id }
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField(placeholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            if searchFocused || !searchText.isEmpty {
                VStack(spacing: 0) {
                    if filteredItems.isEmpty && !searchText.isEmpty {
                        Text("No results matching \"\(searchText)\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { idx, item in
                            itemRow(item)
                            if idx < filteredItems.count - 1 {
                                Divider().padding(.leading, 10)
                            }
                        }
                    }
                    if let createLabel, let onCreate {
                        if !filteredItems.isEmpty || searchText.isEmpty {
                            Divider()
                        }
                        createRow(label: createLabel, action: onCreate)
                    }
                }
                .frame(maxHeight: 200)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func itemRow(_ item: Item) -> some View {
        let sel = isSelected(item)
        return Button { toggle(item) } label: {
            HStack(spacing: 8) {
                Text(label(item))
                    .font(.callout)
                    .foregroundStyle(sel ? chipColor : Color.primary)
                Spacer(minLength: 0)
                if sel {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(chipColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(sel ? chipColor.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func createRow(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(AppTheme.accent)
                    .font(.caption)
                Text(label)
                    .font(.callout)
                    .foregroundStyle(AppTheme.accent)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Convenience init for optional single-select

extension FuzzyPickerField {
    /// Convenience initializer that wraps a `Binding<Item?>` for single-select use.
    init(
        allItems: [Item],
        selectedItem: Binding<Item?>,
        label: @escaping (Item) -> String,
        chipColor: Color,
        placeholder: String = "Search…",
        createLabel: String? = nil,
        onCreate: (() -> Void)? = nil
    ) {
        self.allItems = allItems
        self.label = label
        self.chipColor = chipColor
        self.placeholder = placeholder
        self.maxSelections = 1
        self.createLabel = createLabel
        self.onCreate = onCreate
        self._selected = Binding(
            get: { selectedItem.wrappedValue.map { [$0] } ?? [] },
            set: { selectedItem.wrappedValue = $0.first }
        )
    }
}

// MARK: - RemovableChip (private to this file)

private struct PickerRemovableChip: View {
    let label: String
    let color: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(AppTheme.interfaceFont(size: 10.5, weight: .regular))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 7)
        .padding(.trailing, 5)
        .padding(.vertical, 3)
        .background(AppTheme.chipBackground(color))
        .foregroundStyle(color)
        .overlay(Capsule().stroke(color.opacity(0.85), lineWidth: 1))
        .clipShape(Capsule())
    }
}
