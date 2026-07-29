import SwiftUI

struct DaySectionHeader: View {
    let title: String
    var onAdd: (() -> Void)? = nil
    /// SF Symbol for the trailing button; defaults to the add "+" glyph.
    var systemImage: String = "plus"
    /// A distinct trailing action (e.g. refresh). When set it takes precedence over `onAdd`.
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(AppTheme.interfaceFont(size: 12, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.mutedText)
            Spacer()
            if let action = onAction ?? onAdd {
                Button(action: action) {
                    Image(systemName: systemImage)
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
