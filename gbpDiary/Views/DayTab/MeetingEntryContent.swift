import SwiftUI

// A meeting row in the diary. The whole row is a tap target that opens the meeting minutes in a
// tab (onOpen); the summary is display-only here (edited in the meeting tab).
struct MeetingEntryContent: View {
    let minutes: Minutes?
    var onOpen: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    private var hasSummary: Bool {
        !(minutes?.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    private var displaySummary: String {
        hasSummary ? (minutes?.summary ?? "") : "Untitled meeting"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "calendar")
                .foregroundStyle(AppTheme.project)
                .font(.system(size: 17))
                .frame(width: 22, height: 22)

            HStack(alignment: .center, spacing: 6) {
                Text(displaySummary)
                    .font(.body)
                    .foregroundStyle(hasSummary ? AppTheme.text : AppTheme.mutedText)
                    .lineLimit(1)
                if let minutes {
                    if let project = minutes.projects.first {
                        Chip(label: project.name, color: AppTheme.project)
                    }
                    Chip(label: minutes.meetingAt.formatted(.dateTime.hour().minute()), color: AppTheme.project)
                    if let dur = minutes.duration {
                        Chip(label: dur.displayString, color: AppTheme.duration)
                    }
                }
                Spacer(minLength: 0)
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
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
    }
}
