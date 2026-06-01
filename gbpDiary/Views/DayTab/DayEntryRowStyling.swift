import SwiftUI

struct RowCardStyling: ViewModifier {
    let verticalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal)
            .padding(.vertical, verticalPadding)
    }
}
