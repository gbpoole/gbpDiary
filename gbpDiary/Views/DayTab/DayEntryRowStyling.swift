import SwiftUI

struct RowCardStyling: ViewModifier {
    let selectable: Bool
    let verticalPadding: CGFloat
    let onSelect: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal)
            .padding(.vertical, verticalPadding)
            .simultaneousGesture(TapGesture().onEnded { _ in
                guard selectable else { return }
                onSelect?()
            })
    }
}
