import SwiftUI

struct MeetingEntryContent<InlineText: View>: View {
    let summaryBinding: Binding<String>
    let minutes: Minutes?
    let isEntryFocused: Bool
    let onEdit: (Minutes) -> Void
    @ViewBuilder var inlineText: (Binding<String>) -> InlineText

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(.blue)
                .font(.system(size: 17))
                .frame(width: 22, height: 22)
            HStack(alignment: .center, spacing: 6) {
                inlineText(summaryBinding)
                if let minutes {
                    Chip(label: minutes.meetingAt.formatted(.dateTime.hour().minute()), color: .blue)
                    InlineRowEditButton { onEdit(minutes) }
                }
                if !isEntryFocused { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
    }
}
