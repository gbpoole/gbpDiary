import SwiftUI

// Always-present multi-select action bar for list/table pages (see TasksView, entity list pages).
// Shows "N selected" (or "No selection") on the left and the caller's action buttons on the right,
// disabled while nothing is selected so the bar never pops in and shifts the table. A built-in
// "Clear" button calls `onClear`.
struct BulkActionBar<Actions: View>: View {
    let count: Int
    let onClear: () -> Void
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            Text(count == 0 ? "No selection" : "\(count) selected")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Group {
                actions()
                Button("Clear") { onClear() }
            }
            .disabled(count == 0)
        }
        .buttonStyle(.bordered).controlSize(.small)
        .padding(.horizontal).padding(.bottom, 6)
    }
}
