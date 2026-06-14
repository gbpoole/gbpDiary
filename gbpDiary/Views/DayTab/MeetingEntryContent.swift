import SwiftUI

struct MeetingEntryContent<InlineText: View>: View {
    let summaryBinding: Binding<String>
    let minutes: Minutes?
    let isEntryFocused: Bool
    var isCollapsed: Bool = false
    var onToggleCollapse: (() -> Void)? = nil
    let onEdit: (Minutes) -> Void
    var onDelete: (() -> Void)? = nil
    @ViewBuilder var inlineText: (Binding<String>) -> InlineText

    private func minutesHaveContent(_ minutes: Minutes?) -> Bool {
        guard let note = minutes?.note else { return false }
        return note.blocks.contains {
            $0.kind == .image || !$0.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        let hasContent = minutesHaveContent(minutes)
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "calendar")
                .foregroundStyle(AppTheme.project)
                .font(.system(size: 17))
                .frame(width: 22, height: 22)

            HStack(alignment: .center, spacing: 6) {
                inlineText(summaryBinding)
                if let minutes {
                    if let project = minutes.projects.first {
                        Chip(label: project.name, color: AppTheme.project)
                    }
                    Chip(label: minutes.meetingAt.formatted(.dateTime.hour().minute()), color: AppTheme.project)
                    if let dur = minutes.duration {
                        Chip(label: dur.displayString, color: AppTheme.duration)
                    }
                    if !hasContent {
                        Chip(label: "No minutes", color: AppTheme.mutedText)
                    }
                    if let onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .foregroundStyle(AppTheme.accent)
                                .font(.caption)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !isEntryFocused { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { if let m = minutes { onEdit(m) } }
    }
}
