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

            HStack(alignment: .center, spacing: 6) {
                inlineText(summaryBinding)
                if let minutes {
                    Chip(label: minutes.meetingAt.formatted(.dateTime.hour().minute()), color: .blue)
                    if let dur = minutes.duration {
                        Chip(label: dur.displayString, color: .blue)
                    }
                    InlineRowEditButton { onEdit(minutes) }
                }
                if !isEntryFocused { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
    }
}
