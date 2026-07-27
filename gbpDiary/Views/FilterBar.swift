import SwiftUI

// MARK: - Filter engine (pure, testable)

/// Applies a set of active `PickerFilter`s to a collection using the same semantics as the
/// FuzzyPickerField filter popover:
///
/// - **OR within a group** — an item passes a group if it matches *any* active filter in that group.
/// - **AND across groups** — an item is kept only if it passes *every* group that has an active filter.
/// - A group with no active filter is ignored entirely (does not narrow the result).
/// - When nothing is active, all items are returned unchanged.
enum FilterEngine {
    static func apply<Item>(
        _ items: [Item],
        filters: [PickerFilter<Item>],
        activeIds: Set<String>
    ) -> [Item] {
        let active = filters.filter { activeIds.contains($0.id) }
        guard !active.isEmpty else { return items }
        let groups = Dictionary(grouping: active, by: { $0.group })
        return items.filter { item in
            groups.values.allSatisfy { groupFilters in
                groupFilters.contains { $0.test(item) }
            }
        }
    }
}

// MARK: - FilterBar

/// A reusable page-level filter bar built from the same pattern as the FuzzyPickerField popover:
/// one neutral dropdown per filter group with the chosen values shown as removable chips beside it.
///
/// The owning view holds `activeFilterIds` as `@State`, builds `filters` from its queried data, and
/// applies them to its list via `FilterEngine.apply`. Pass `extraRows` for non-discrete filters
/// (e.g. a date range) and `onClearAll` to reset every filter the page owns.
struct FilterBar<Item>: View {
    let filters: [PickerFilter<Item>]
    @Binding var activeFilterIds: Set<String>
    var defaultChipColor: Color = AppTheme.accent
    /// True when the page has an active filter that `activeFilterIds` doesn't track (e.g. a date range).
    var hasExtraActiveFilter: Bool = false
    /// Extra rows rendered below the group rows (same horizontal insets), e.g. a date-range selector.
    var extraRows: AnyView? = nil
    var onClearAll: () -> Void = {}

    private var isActive: Bool { !activeFilterIds.isEmpty || hasExtraActiveFilter }

    private var orderedGroups: [(name: String?, filters: [PickerFilter<Item>])] {
        var seen = Set<String?>()
        var order: [String?] = []
        for f in filters where seen.insert(f.group).inserted { order.append(f.group) }
        return order.map { name in (name, filters.filter { $0.group == name }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Heading so the row of neutral dropdowns reads unambiguously as filters.
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10, weight: .semibold))
                Text("Filter")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                if isActive {
                    Button("Clear all") { onClearAll() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .foregroundStyle(AppTheme.mutedText)

            // One row per filter group: the dropdown (aligned in a fixed-width column) on the
            // left, the chosen values as removable chips flowing to the right. Indented so the
            // dropdowns sit visually under the "Filter" heading.
            VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(orderedGroups.enumerated()), id: \.offset) { _, group in
                let active = group.filters.filter { activeFilterIds.contains($0.id) }
                let groupColor = group.filters.first?.chipColor ?? defaultChipColor
                HStack(alignment: .top, spacing: 6) {
                    FilterGroupSelector(
                        name: group.name,
                        groupFilters: group.filters,
                        defaultColor: defaultChipColor,
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

            if let extraRows { extraRows }
            }
            .padding(.leading, 12)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(AppTheme.sidebarBackground)
    }
}
