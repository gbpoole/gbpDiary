import SwiftUI

struct InlineRowEditButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .buttonStyle(.plain)
    }
}
