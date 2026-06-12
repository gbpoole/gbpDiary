import SwiftUI

struct RowCardStyling: ViewModifier {
    let verticalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppTheme.border.opacity(0.9), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
            )
            .padding(.horizontal)
            .padding(.vertical, verticalPadding)
    }
}
