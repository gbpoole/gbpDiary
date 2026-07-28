import SwiftUI

// MARK: - Action data model

/// Platform-agnostic description of one day-level creation action.
/// DayPageContent builds a [DayActionItem] list once; macOS renders it as a
/// centered bar (DayActionBar) and iOS will render the same list as a FAB.
struct DayActionItem: Identifiable {
    let id: String
    let systemName: String
    let color: Color
    let tooltip: String
    var isEnabled: Bool = true
    let action: () -> Void
    /// When non-empty, the item opens a menu of these choices instead of firing `action`.
    var menuItems: [DayActionMenuItem] = []
}

/// One choice within a `DayActionItem`'s dropdown menu.
struct DayActionMenuItem: Identifiable {
    let id: String
    let title: String
    let systemName: String
    let action: () -> Void
}

// MARK: - macOS presentation: centered horizontal bar

struct DayActionBar: View {
    let items: [DayActionItem]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                HStack(spacing: 24) {
                    ForEach(items) { item in
                        if item.menuItems.isEmpty {
                            Button(action: item.action) { icon(item) }
                                .buttonStyle(.plain)
                                .help(item.tooltip)
                                .disabled(!item.isEnabled)
                        } else {
                            Menu {
                                ForEach(item.menuItems) { choice in
                                    Button(action: choice.action) {
                                        Label(choice.title, systemImage: choice.systemName)
                                    }
                                }
                            } label: { icon(item) }
                            .menuStyle(.button)
                            .buttonStyle(.plain)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help(item.tooltip)
                            .disabled(!item.isEnabled)
                        }
                    }
                }
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
            Divider().padding(.horizontal)
        }
    }

    private func icon(_ item: DayActionItem) -> some View {
        Image(systemName: item.systemName)
            .font(.system(size: 17))
            .foregroundStyle(item.color)
    }
}
