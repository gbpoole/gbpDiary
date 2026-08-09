import SwiftUI

/// The Tasks page's compact filter/search toolbar — a thin wrapper over the shared `ListToolbar`
/// that supplies the Tasks-specific preset chips (six one-tap filter toggles + the mutually-exclusive
/// Today/Week/Month date trio) and the custom date-range slot (popover row + active chip).
struct TasksToolbar: View {
    let filters: [PickerFilter<Task>]
    @Bindable var filter: TasksFilterState

    // Preset chips that toggle a single `activeFilterId`.
    private let filterPresets: [(label: String, id: String)] = [
        ("Incomplete", "preset.incomplete"),
        ("From email", "source.email"),
        ("Overdue",    "flag.overdue"),
        ("Due today",  "flag.dueToday"),
        ("Mine",       "preset.mine"),
        ("Others",     "preset.others"),
    ]

    private var presets: [ToolbarPreset] {
        let idPresets = filterPresets.map { p in
            ToolbarPreset(id: p.id, label: p.label, isActive: filter.activeFilterIds.contains(p.id)) {
                toggle(p.id)
            }
        }
        let datePresets = DateWindow.allCases.map { window in
            ToolbarPreset(id: "date.\(window.rawValue)", label: window.label,
                          isActive: filter.datePreset == window) { toggleDate(window) }
        }
        return idPresets + datePresets
    }

    var body: some View {
        ListToolbar(
            searchText: $filter.searchText,
            searchPrompt: "Search tasks…",
            presets: presets,
            filters: filters,
            activeFilterIds: $filter.activeFilterIds,
            extraPopover: AnyView(DateRangeFilterRow(range: Binding(
                get: { filter.dateRange },
                set: { filter.dateRange = $0; filter.datePreset = nil }   // custom range clears the preset chip
            ))),
            extraActiveChips: filter.dateRange.map { range in
                AnyView(PickerRemovableChip(label: dateChipLabel(range), color: AppTheme.accent) {
                    filter.dateRange = nil; filter.datePreset = nil
                })
            },
            hasExtraActiveFilter: filter.dateRange != nil,
            onClearAll: { clearAll() }
        )
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
