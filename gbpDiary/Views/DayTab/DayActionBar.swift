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
                        Button(action: item.action) { icon(item) }
                            .buttonStyle(.plain)
                            .help(item.tooltip)
                            .disabled(!item.isEnabled)
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
