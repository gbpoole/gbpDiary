import SwiftUI

/// A reusable search-filter selector with chips for selected items.
///
/// The form row shows chips + a fixed-height trigger button. Tapping it opens a
/// popover that floats above all other content — so the surrounding form layout
/// never shifts. Supports multi-select (default) and single-select (`maxSelections: 1`).
struct FuzzyPickerField<Item: Identifiable>: View {
    let allItems: [Item]
    @Binding var selected: [Item]
    let label: (Item) -> String
    let chipColor: Color
    var placeholder: String = "Search…"
    var maxSelections: Int = Int.max
    var createLabel: String? = nil
    var onCreate: (() -> Void)? = nil
    /// When true the whole row is the tap target and no icon is shown.
    /// `emptyLabel` is displayed in the accent color when nothing is selected.
    var tapArea: Bool = false
    var emptyLabel: String? = nil

    @State private var isPopoverOpen = false

    var body: some View {
        if tapArea {
            tapAreaBody
        } else {
            iconBody
        }
    }

    // MARK: - Icon style (default)

    private var iconBody: some View {
        HStack(alignment: .center, spacing: 6) {
            if !selected.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(selected) { item in
                        PickerRemovableChip(label: label(item), color: chipColor) {
                            selected.removeAll { $0.id == item.id }
                        }
                    }
                }
            }

            // Compact icon trigger — opens the floating popover.
            Button { isPopoverOpen = true } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.accent)
                    .font(.caption)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPopoverOpen, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                popoverContent
            }
        }
    }

    // MARK: - Tap-area style (no icon; whole row opens picker)

    private var tapAreaBody: some View {
        Button { isPopoverOpen = true } label: {
            HStack(alignment: .center, spacing: 6) {
                if selected.isEmpty {
                    Text(emptyLabel ?? placeholder)
                        .foregroundStyle(AppTheme.accent)
                        .font(.callout)
                } else {
                    HStack(alignment: .center, spacing: 4) {
                        ForEach(selected) { item in
                            PickerRemovableChip(label: label(item), color: chipColor) {
                                selected.removeAll { $0.id == item.id }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPopoverOpen, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            popoverContent
        }
    }

    // MARK: - Shared popover content

    private var popoverContent: some View {
        PickerPopoverContent(
            allItems: allItems,
            selected: $selected,
            label: label,
            chipColor: chipColor,
            placeholder: placeholder,
            maxSelections: maxSelections,
            createLabel: createLabel,
            onCreate: onCreate,
            dismiss: { isPopoverOpen = false }
        )
        .frame(minWidth: 260, maxHeight: 320)
    }
}

// MARK: - Popover content

private struct PickerPopoverContent<Item: Identifiable>: View {
    let allItems: [Item]
    @Binding var selected: [Item]
    let label: (Item) -> String
    let chipColor: Color
    var placeholder: String
    var maxSelections: Int
    var createLabel: String?
    var onCreate: (() -> Void)?
    var dismiss: () -> Void

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var highlightedIndex: Int? = nil
    // Local @State mirror of selected so the popover's own view graph
    // re-renders reliably on every mutation, independent of binding propagation.
    @State private var localSelected: [Item] = []

    private var filteredItems: [Item] {
        let unselected = allItems.filter { item in !localSelected.contains(where: { $0.id == item.id }) }
        guard !searchText.isEmpty else { return unselected }
        let q = searchText.lowercased()
        return unselected.filter { label($0).lowercased().contains(q) }
    }

    private func isSelected(_ item: Item) -> Bool {
        localSelected.contains(where: { $0.id == item.id })
    }

    private func toggle(_ item: Item) {
        if isSelected(item) {
            localSelected.removeAll { $0.id == item.id }
        } else {
            if maxSelections == 1 {
                localSelected = [item]
                selected = localSelected
                dismiss()
                return
            } else if localSelected.count < maxSelections {
                localSelected.append(item)
            }
        }
        selected = localSelected
        searchText = ""
        highlightedIndex = nil
    }

    private func moveHighlight(by delta: Int) {
        guard !filteredItems.isEmpty else { return }
        let count = filteredItems.count
        if let current = highlightedIndex {
            highlightedIndex = max(0, min(count - 1, current + delta))
        } else {
            highlightedIndex = delta > 0 ? 0 : count - 1
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($searchFocused)
                    .onKeyPress(.upArrow, phases: .down) { _ in
                        moveHighlight(by: -1); return .handled
                    }
                    .onKeyPress(.downArrow, phases: .down) { _ in
                        moveHighlight(by: 1); return .handled
                    }
                    .onKeyPress(.return, phases: .down) { _ in
                        if let idx = highlightedIndex, idx < filteredItems.count {
                            toggle(filteredItems[idx])
                        }
                        return .handled
                    }
                    .onKeyPress(.escape, phases: .down) { _ in
                        dismiss(); return .handled
                    }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Selected items (multi-select only) — pinned above the scrollable list,
            // scrollable so a large selection doesn't crowd out the item list.
            // Cursor navigation skips this section entirely.
            if maxSelections != 1 && !localSelected.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(localSelected) { item in
                            selectedItemRow(item)
                        }
                    }
                }
                .frame(maxHeight: 120)
                Divider()
            }

            // Filterable list — cursor navigation (highlightedIndex) applies here only.
            ScrollView {
                VStack(spacing: 0) {
                    if filteredItems.isEmpty && !searchText.isEmpty {
                        Text("No results matching \"\(searchText)\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { idx, item in
                            itemRow(item, highlighted: highlightedIndex == idx)
                            if idx < filteredItems.count - 1 {
                                Divider().padding(.leading, 10)
                            }
                        }
                    }
                    if let createLabel, let onCreate {
                        if !filteredItems.isEmpty || searchText.isEmpty { Divider() }
                        createRow(label: createLabel, action: onCreate)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .onAppear {
            localSelected = selected
            searchFocused = true
        }
        // Keep localSelected in sync if chips are removed from the form while open.
        .onChange(of: selected.count) { _, _ in localSelected = selected }
        .onChange(of: searchText) { _, _ in highlightedIndex = nil }
    }

    private func selectedItemRow(_ item: Item) -> some View {
        HStack(spacing: 8) {
            Text(label(item))
                .font(.callout)
                .foregroundStyle(chipColor)
            Spacer(minLength: 0)
            Button {
                localSelected.removeAll { $0.id == item.id }
                selected = localSelected
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(chipColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(chipColor.opacity(0.08))
    }

    private func itemRow(_ item: Item, highlighted: Bool) -> some View {
        let bg: Color = highlighted ? chipColor.opacity(0.15) : Color.clear
        return Button { toggle(item) } label: {
            HStack(spacing: 8) {
                Text(label(item))
                    .font(.callout)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(bg)
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
        tapArea: Bool = false,
        emptyLabel: String? = nil,
        createLabel: String? = nil,
        onCreate: (() -> Void)? = nil
    ) {
        self.allItems = allItems
        self.label = label
        self.chipColor = chipColor
        self.placeholder = placeholder
        self.maxSelections = 1
        self.tapArea = tapArea
        self.emptyLabel = emptyLabel
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
