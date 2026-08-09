import SwiftUI

// A one-tap preset chip descriptor for `ListToolbar` (label + lit state + toggle action).
struct ToolbarPreset: Identifiable {
    let id: String
    let label: String
    let isActive: Bool
    let toggle: () -> Void
}

// The canonical compact toolbar for list/table pages. One wrapping block:
//  • a compact capsule fuzzy-search field (always present),
//  • optional one-tap `PresetChip`s,
//  • a "Filters ▾" popover of `FilterGroupSelector` rows (only when the page has filters), and
//  • an always-present active-filter row ("none" when empty, pinned height, inline "Clear all").
// When `filters` is empty and no `extraPopover` is supplied it collapses to search-only (the Light
// tier). `extra*` slots carry non-discrete filters such as the Tasks page's date range.
struct ListToolbar<Item>: View {
    @Binding var searchText: String
    var searchPrompt: String = "Search…"
    var presets: [ToolbarPreset] = []
    var filters: [PickerFilter<Item>] = []
    @Binding var activeFilterIds: Set<String>
    var extraPopover: AnyView? = nil
    var extraActiveChips: AnyView? = nil
    var hasExtraActiveFilter: Bool = false
    var onClearAll: () -> Void = {}

    @State private var showingFilters = false

    private var hasFilters: Bool { !filters.isEmpty || extraPopover != nil }
    private var isActive: Bool { !activeFilterIds.isEmpty || hasExtraActiveFilter }
    private var activeChips: [PickerFilter<Item>] { filters.filter { activeFilterIds.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                searchField
                if hasFilters {
                    filtersButton
                }
                Spacer(minLength: 0)
            }

            if !presets.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(presets) { preset in
                        PresetChip(label: preset.label, isActive: preset.isActive) { preset.toggle() }
                    }
                }
            }

            if hasFilters {
                activeFilterRow
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(AppTheme.sidebarBackground)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField(searchPrompt, text: $searchText)
                .textFieldStyle(.plain).font(.callout)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .frame(maxWidth: 240)
    }

    private var filtersButton: some View {
        Button { showingFilters = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 10, weight: .semibold))
                Text("Filters").font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingFilters, arrowEdge: .bottom) { filtersPopover }
    }

    private var activeFilterRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Active filters")
                .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.mutedText)
            if isActive {
                FlowLayout(spacing: 5, centerVertically: true) {
                    ForEach(activeChips) { f in
                        PickerRemovableChip(label: f.label, color: f.chipColor ?? AppTheme.accent) {
                            activeFilterIds.remove(f.id)
                        }
                    }
                    if let extraActiveChips { extraActiveChips }
                    Button("Clear all") { onClearAll() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(AppTheme.accent)
                }
            } else {
                Text("none")
                    .font(.caption).foregroundStyle(AppTheme.mutedText.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 22)   // keep a constant height whether or not chips are present
    }

    private var filtersPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(orderedGroups.enumerated()), id: \.offset) { _, group in
                FilterGroupSelector(
                    name: group.name,
                    groupFilters: group.filters,
                    defaultColor: AppTheme.accent,
                    activeFilterIds: $activeFilterIds
                )
            }
            if let extraPopover { extraPopover }
            if isActive {
                Divider()
                Button("Clear all filters") { onClearAll() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(AppTheme.accent)
            }
        }
        .padding()
        .frame(minWidth: 260)
    }

    private var orderedGroups: [(name: String?, filters: [PickerFilter<Item>])] {
        var seen = Set<String?>()
        var order: [String?] = []
        for f in filters where seen.insert(f.group).inserted { order.append(f.group) }
        return order.map { name in (name, filters.filter { $0.group == name }) }
    }
}

// A small toggleable pill for list-toolbar presets — tinted when active, outlined when not.
struct PresetChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AppTheme.interfaceFont(size: 11, weight: isActive ? .medium : .regular))
                .lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(isActive ? AppTheme.chipBackground(AppTheme.accent) : Color.clear)
                .foregroundStyle(isActive ? AppTheme.accent : AppTheme.mutedText)
                .overlay(Capsule().stroke(isActive ? AppTheme.accent.opacity(0.85) : AppTheme.mutedText.opacity(0.35), lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
