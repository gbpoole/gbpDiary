import SwiftUI

// MARK: - PickerFilter

/// A named predicate used to narrow the items shown inside a FuzzyPickerField popover.
/// Pass an array via `filters:` to show labeled rows of toggle chips above the item list.
/// Only one filter can be active at a time; tapping the active chip deactivates it.
/// Set `chipColor` to distinguish filter types visually (e.g. blue for projects, mauve for institutions).
/// Set `group` (e.g. "Project", "Institution", "Tag") to group chips into labeled rows.
struct PickerFilter<Item>: Identifiable {
    let id: String
    let label: String
    var chipColor: Color? = nil
    var group: String? = nil
    let test: (Item) -> Bool
}

// MARK: - FuzzyPickerField

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
    /// When set, a "Add 'X'" row appears in the popover while the user is typing.
    /// The closure receives the trimmed search text and returns the new item to select.
    var onCreateItem: ((String) -> Item?)? = nil
    /// Controls whether a newly created item (via `onCreateItem`) is automatically
    /// added to the selection. Default `true`. Set to `false` when the creation is
    /// a side-effect (e.g. inserting a SwiftData entity) but selection is not desired.
    var autoSelectOnCreate: Bool = true
    /// When true the whole row is the tap target and no icon is shown.
    /// `emptyLabel` is displayed in the accent color when nothing is selected.
    var tapArea: Bool = false
    var emptyLabel: String? = nil
    /// Optional filter chips shown in the popover between the search field and the
    /// item list. At most one filter can be active at a time.
    var filters: [PickerFilter<Item>]? = nil
    /// ID of the filter that should be active when the popover first opens.
    var defaultFilterId: String? = nil
    /// When provided, the caller controls whether the popover is open.
    /// Useful for opening the picker programmatically from another view.
    var isPresented: Binding<Bool>? = nil
    /// Optional view injected at the top of the filter area, above any filter chips.
    /// Use this to show a context row (e.g. a current project filter with a link to change it).
    var filterLeadContent: AnyView? = nil
    /// When true, the tap-area button steals keyboard focus on appear so the user
    /// can press Return to open the picker without clicking first.
    var autoFocus: Bool = false

    @State private var isPopoverOpen = false
    @FocusState private var buttonFocused: Bool

    /// Returns the external binding when provided, otherwise the internal @State.
    private var popoverIsOpen: Binding<Bool> { isPresented ?? $isPopoverOpen }

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
            Button { popoverIsOpen.wrappedValue = true } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.accent)
                    .font(.caption)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: popoverIsOpen, arrowEdge: .bottom) {
                popoverContent
            }
        }
    }

    // MARK: - Tap-area style (no icon; whole row opens picker)

    private var tapAreaBody: some View {
        Button { popoverIsOpen.wrappedValue = true } label: {
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
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($buttonFocused)
        .onKeyPress(.return, phases: .down) { _ in
            popoverIsOpen.wrappedValue = true
            return .handled
        }
        .popover(isPresented: popoverIsOpen, arrowEdge: .bottom) {
            popoverContent
        }
        .onAppear {
            if autoFocus {
                DispatchQueue.main.async { buttonFocused = true }
            }
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
            onCreateItem: onCreateItem,
            autoSelectOnCreate: autoSelectOnCreate,
            filters: filters,
            defaultFilterId: defaultFilterId,
            filterLeadContent: filterLeadContent,
            dismiss: { popoverIsOpen.wrappedValue = false }
        )
        .frame(width: 340)
        .frame(maxHeight: 320)
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
    var onCreateItem: ((String) -> Item?)?
    var autoSelectOnCreate: Bool
    var filters: [PickerFilter<Item>]?
    var defaultFilterId: String? = nil
    var filterLeadContent: AnyView? = nil
    var dismiss: () -> Void

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var highlightedIndex: Int? = nil
    // Active filter ids. Within a group they combine with OR; groups combine with AND.
    @State private var activeFilterIds: Set<String> = []
    // Local @State mirror of selected so the popover's own view graph
    // re-renders reliably on every mutation, independent of binding propagation.
    @State private var localSelected: [Item] = []

    private var filteredItems: [Item] {
        var items = allItems.filter { item in !localSelected.contains(where: { $0.id == item.id }) }
        if let filters, !activeFilterIds.isEmpty {
            // Each group narrows independently (AND across groups); within a group the active
            // filters are OR'd, so an item passes a group if it matches any active filter there.
            for (_, groupFilters) in orderedGroups(from: filters) {
                let active = groupFilters.filter { activeFilterIds.contains($0.id) }
                guard !active.isEmpty else { continue }
                items = items.filter { item in active.contains { $0.test(item) } }
            }
        }
        guard !searchText.isEmpty else { return items }
        let q = searchText.lowercased()
        return items.filter { label($0).lowercased().contains(q) }
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

    private func commitCreate(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !localSelected.contains(where: { label($0) == trimmed }),
              let newItem = onCreateItem?(trimmed) else { return }
        if autoSelectOnCreate, !localSelected.contains(where: { $0.id == newItem.id }) {
            localSelected.append(newItem)
            selected = localSelected
        }
        searchText = ""
        highlightedIndex = nil
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
                        } else if onCreateItem != nil {
                            commitCreate(text: searchText)
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

            // Filter area — lead content (e.g. a project context row) followed by
            // grouped filter chip rows. Only rendered when something is present.
            let hasFilterArea = filterLeadContent != nil || !(filters?.isEmpty ?? true)
            if hasFilterArea {
                VStack(spacing: 0) {
                    if let lead = filterLeadContent { lead }
                    if let filters, !filters.isEmpty { filterSection(filters) }
                }
                Divider()
            }

            let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
            let hasListContent = !filteredItems.isEmpty
                || !searchText.isEmpty
                || (createLabel != nil && onCreate != nil)

            // Selected items (multi-select only) — pinned above the scrollable list,
            // scrollable so a large selection doesn't crowd out the item list.
            // Cursor navigation skips this section entirely.
            if maxSelections != 1 && !localSelected.isEmpty {
                let selectedRows = VStack(spacing: 0) {
                    ForEach(localSelected) { item in
                        selectedItemRow(item)
                    }
                }
                if !hasListContent {
                    // No options list to show (e.g. everything selected) — let the selected
                    // section expand into that space so the popover keeps the same overall
                    // height instead of shrinking and re-centering on its anchor.
                    ScrollView { selectedRows }.frame(maxHeight: .infinity)
                } else if localSelected.count > 4 {
                    // Cap and scroll a long selection so it doesn't crowd out the item list.
                    ScrollView { selectedRows }.frame(maxHeight: 120)
                } else {
                    // Short selection with a list below — hug the content so there's no gap.
                    selectedRows
                }
                if hasListContent { Divider() }
            }

            // Filterable list — only rendered when there is something to show so that
            // the flexible ScrollView doesn't consume space when empty.
            if hasListContent {
                ScrollView {
                    VStack(spacing: 0) {
                        // Suppress "no results" when the create row will appear — it's self-explanatory.
                        let createRowWillShow = onCreateItem != nil
                            && !trimmedSearch.isEmpty
                            && !localSelected.contains(where: { label($0) == trimmedSearch })
                        if filteredItems.isEmpty && !searchText.isEmpty && !createRowWillShow {
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
                        if let onCreateItem {
                            if !trimmedSearch.isEmpty, !localSelected.contains(where: { label($0) == trimmedSearch }) {
                                if !filteredItems.isEmpty { Divider().padding(.leading, 10) }
                                createRow(label: "Add \"\(trimmedSearch)\"") {
                                    if let newItem = onCreateItem(trimmedSearch) {
                                        if autoSelectOnCreate,
                                           !localSelected.contains(where: { $0.id == newItem.id }) {
                                            localSelected.append(newItem)
                                            selected = localSelected
                                        }
                                    }
                                    searchText = ""
                                    highlightedIndex = nil
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
        }
        .onAppear {
            localSelected = selected
            searchFocused = true
            if let defaultId = defaultFilterId { activeFilterIds = [defaultId] }
        }
        // Keep localSelected in sync if chips are removed from the form while open.
        .onChange(of: selected.count) { _, _ in localSelected = selected }
        .onChange(of: searchText) { _, _ in highlightedIndex = nil }
    }

    // MARK: - Filter section helpers

    private func filterSection(_ filters: [PickerFilter<Item>]) -> some View {
        let groups = orderedGroups(from: filters)
        return VStack(alignment: .leading, spacing: 6) {
            // One row per filter parameter: the dropdown (aligned in a fixed-width column) on the
            // left, the chosen values as removable chips to the right.
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                let active = group.filters.filter { activeFilterIds.contains($0.id) }
                let groupColor = group.filters.first?.chipColor ?? chipColor
                HStack(alignment: .top, spacing: 6) {
                    FilterGroupSelector(
                        name: group.name,
                        groupFilters: group.filters,
                        defaultColor: chipColor,
                        activeFilterIds: $activeFilterIds
                    )
                    .frame(width: 104, alignment: .leading)

                    if !active.isEmpty {
                        FlowLayout(spacing: 4) {
                            ForEach(active) { filter in
                                PickerRemovableChip(label: filter.label, color: groupColor) {
                                    activeFilterIds.remove(filter.id)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func orderedGroups(from filters: [PickerFilter<Item>]) -> [(name: String?, filters: [PickerFilter<Item>])] {
        var seen: [String?: Bool] = [:]
        var order: [String?] = []
        for f in filters {
            if seen[f.group] == nil { seen[f.group] = true; order.append(f.group) }
        }
        return order.map { name in (name, filters.filter { $0.group == name }) }
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
        onCreateItem: ((String) -> Item?)? = nil,
        autoSelectOnCreate: Bool = true,
        tapArea: Bool = false,
        emptyLabel: String? = nil,
        createLabel: String? = nil,
        onCreate: (() -> Void)? = nil,
        filters: [PickerFilter<Item>]? = nil,
        defaultFilterId: String? = nil,
        isPresented: Binding<Bool>? = nil,
        filterLeadContent: AnyView? = nil,
        autoFocus: Bool = false
    ) {
        self.allItems = allItems
        self.label = label
        self.chipColor = chipColor
        self.placeholder = placeholder
        self.maxSelections = 1
        self.onCreateItem = onCreateItem
        self.autoSelectOnCreate = autoSelectOnCreate
        self.tapArea = tapArea
        self.emptyLabel = emptyLabel
        self.createLabel = createLabel
        self.onCreate = onCreate
        self.filters = filters
        self.defaultFilterId = defaultFilterId
        self.isPresented = isPresented
        self.filterLeadContent = filterLeadContent
        self.autoFocus = autoFocus
        self._selected = Binding(
            get: { selectedItem.wrappedValue.map { [$0] } ?? [] },
            set: { selectedItem.wrappedValue = $0.first }
        )
    }
}

// MARK: - Filter group selector
//
// One compact dropdown per filter group. Tapping opens a searchable, multi-select list (same
// visual language as the main picker) so long option lists — e.g. institutions — stay tidy and
// searchable instead of overflowing a horizontal chip row. Values within a group combine with OR.
private struct FilterGroupSelector<Item>: View {
    let name: String?
    let groupFilters: [PickerFilter<Item>]
    let defaultColor: Color
    @Binding var activeFilterIds: Set<String>

    @State private var open = false
    @State private var search = ""

    private var color: Color { groupFilters.first?.chipColor ?? defaultColor }
    private var activeInGroup: [PickerFilter<Item>] { groupFilters.filter { activeFilterIds.contains($0.id) } }
    private var isActive: Bool { !activeInGroup.isEmpty }

    private var matching: [PickerFilter<Item>] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return groupFilters }
        return groupFilters.filter { $0.label.lowercased().contains(q) }
    }

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 5) {
                Text(name ?? "Filter")
                    .font(.caption)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            listPopover
        }
    }

    private var listPopover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                TextField("Search…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.callout)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(matching) { filter in
                        let on = activeFilterIds.contains(filter.id)
                        Button {
                            if on { activeFilterIds.remove(filter.id) } else { activeFilterIds.insert(filter.id) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? color : Color.secondary)
                                Text(filter.label).font(.callout)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 10)
                    }
                }
            }
            .frame(maxHeight: 240)
            if isActive {
                Divider()
                Button {
                    for f in groupFilters { activeFilterIds.remove(f.id) }
                } label: {
                    Text("Clear \(name ?? "filter")").font(.caption).foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 220, maxHeight: 340)
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
