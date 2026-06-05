import SwiftUI

struct MeetingEntryContent<InlineText: View>: View {
    let summaryBinding: Binding<String>
    let minutes: Minutes?
    let isEntryFocused: Bool
    var isCollapsed: Bool = false
    var onToggleCollapse: (() -> Void)? = nil
    let onEdit: (Minutes) -> Void
    @ViewBuilder var inlineText: (Binding<String>) -> InlineText

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .center, spacing: 6) {
                Button(action: { onToggleCollapse?() }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())

                Image(systemName: "calendar")
                    .foregroundStyle(.blue)
                    .font(.system(size: 17))
                    .frame(width: 22, height: 22)

                if let minutes {
                    Chip(label: minutes.meetingAt.formatted(.dateTime.hour().minute()), color: .blue)
                }
                Spacer(minLength: 0)
                if let minutes {
                    InlineRowEditButton { onEdit(minutes) }
                }
            }

            inlineText(summaryBinding)
                .padding(.leading, 50)
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
    }
}
