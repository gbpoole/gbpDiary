import SwiftUI

struct DaySectionHeader: View {
    let title: String
    var onAdd: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Spacer()
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}
