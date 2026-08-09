import SwiftUI

/// The Tasks page's compact filter/search toolbar. Replaces the tall shared `FilterBar` on this
/// page with a single wrapping row: a compact capsule search, one-tap **preset chips** for the
/// common filters, a **Filters ▾** popover holding the detailed per-field pickers, and a removable
/// active-filter chip row. The `FilterEngine`/`PickerFilter` logic is reused unchanged.
struct TasksToolbar: View {
    let filters: [PickerFilter<Task>]
    @Bindable var filter: TasksFilterState

    @State private var showingFilters = false

    // Preset chips that toggle a single `activeFilterId`.
    private let presets: [(label: String, id: String)] = [
        ("Incomplete", "preset.incomplete"),
        ("From email", "source.email"),
        ("Overdue",    "flag.overdue"),
        ("Due today",  "flag.dueToday"),
        ("Mine",       "preset.mine"),
        ("Others",     "preset.others"),
    ]

    private var isActive: Bool { !filter.activeFilterIds.isEmpty || filter.dateRange != nil }

    private var activeChips: [PickerFilter<Task>] {
        filters.filter { filter.activeFilterIds.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                searchField
                Button { showingFilters = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Filters").font(.caption)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingFilters, arrowEdge: .bottom) { filtersPopover }
                Spacer(minLength: 0)
            }

            FlowLayout(spacing: 6) {
                ForEach(presets, id: \.id) { preset in
                    PresetChip(label: preset.label, isActive: filter.activeFilterIds.contains(preset.id)) {
                        toggle(preset.id)
                    }
                }
                ForEach(DateWindow.allCases, id: \.self) { window in
                    PresetChip(label: window.label, isActive: filter.datePreset == window) {
                        toggleDate(window)
                    }
                }
            }

            if isActive {
                FlowLayout(spacing: 5) {
                    Text("Active filters")
                        .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.mutedText)
                    ForEach(activeChips) { f in
                        PickerRemovableChip(label: f.label, color: f.chipColor ?? AppTheme.accent) {
                            filter.activeFilterIds.remove(f.id)
                        }
                    }
                    if let range = filter.dateRange {
                        PickerRemovableChip(label: dateChipLabel(range), color: AppTheme.accent) {
                            filter.dateRange = nil; filter.datePreset = nil
                        }
                    }
                    Button("Clear all") { clearAll() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(AppTheme.accent)
                }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(AppTheme.sidebarBackground)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField("Find tasks…", text: $filter.searchText)
                .textFieldStyle(.plain).font(.callout)
            if !filter.searchText.isEmpty {
                Button { filter.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .frame(maxWidth: 240)
    }

    // Detailed per-field pickers, mirroring the shared FilterBar's group rows.
    private var filtersPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(orderedGroups.enumerated()), id: \.offset) { _, group in
                FilterGroupSelector(
                    name: group.name,
                    groupFilters: group.filters,
                    defaultColor: AppTheme.accent,
                    activeFilterIds: $filter.activeFilterIds
                )
            }
            DateRangeFilterRow(range: Binding(
                get: { filter.dateRange },
                set: { filter.dateRange = $0; filter.datePreset = nil }   // custom range clears the preset chip
            ))
            if isActive {
                Divider()
                Button("Clear all filters") { clearAll() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(AppTheme.accent)
            }
        }
        .padding()
        .frame(minWidth: 260)
    }

    private var orderedGroups: [(name: String?, filters: [PickerFilter<Task>])] {
        var seen = Set<String?>()
        var order: [String?] = []
        for f in filters where seen.insert(f.group).inserted { order.append(f.group) }
        return order.map { name in (name, filters.filter { $0.group == name }) }
    }

    private func toggle(_ id: String) {
        if filter.activeFilterIds.contains(id) { filter.activeFilterIds.remove(id) }
        else { filter.activeFilterIds.insert(id) }
    }

    private func toggleDate(_ window: DateWindow) {
        if filter.datePreset == window {
            filter.datePreset = nil; filter.dateRange = nil
        } else {
            filter.datePreset = window; filter.dateRange = window.range()
        }
    }

    private func clearAll() {
        filter.activeFilterIds = []
        filter.dateRange = nil
        filter.datePreset = nil
    }

    private func dateChipLabel(_ range: ClosedRange<Date>) -> String {
        if let preset = filter.datePreset { return preset.label }
        let fmt = DateFormatter(); fmt.dateStyle = .short
        return "\(fmt.string(from: range.lowerBound)) – \(fmt.string(from: range.upperBound))"
    }
}

/// A small toggleable pill for the Tasks toolbar presets — tinted when active, outlined when not.
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
