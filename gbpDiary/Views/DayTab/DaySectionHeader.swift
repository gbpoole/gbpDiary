import SwiftUI

struct DaySectionHeader: View {
    let title: String
    var onAdd: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(AppTheme.interfaceFont(size: 12, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.mutedText)
            Spacer()
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .background(AppTheme.background)
    }
}
