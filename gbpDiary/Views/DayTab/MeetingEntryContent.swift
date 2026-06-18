import SwiftUI

// Flag class lets buttons set state synchronously before .onChange fires.
private final class MeetingTapFlags { var didTapMinutesAction = false }

struct MeetingEntryContent<InlineText: View>: View {
    let summaryBinding: Binding<String>
    let minutes: Minutes?
    let isEntryFocused: Bool
    var isCollapsed: Bool = false
    var onToggleCollapse: (() -> Void)? = nil
    var onAddMinutes: (() -> Void)? = nil
    var onOpenMinutes: (() -> Void)? = nil
    let onEdit: (Minutes) -> Void
    var onDelete: (() -> Void)? = nil
    @ViewBuilder var inlineText: (Binding<String>) -> InlineText

    @State private var tapFlags = MeetingTapFlags()
    @State private var editTapCount = 0

    var body: some View {
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
                    minutesChip(for: minutes)
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
        .simultaneousGesture(TapGesture().onEnded { editTapCount += 1 })
        .onChange(of: editTapCount) {
            if tapFlags.didTapMinutesAction {
                tapFlags.didTapMinutesAction = false
            } else if let m = minutes {
                onEdit(m)
            }
        }
    }

    @ViewBuilder
    private func minutesChip(for minutes: Minutes) -> some View {
        if minutes.note == nil {
            if let onAddMinutes {
                Button("Add minutes") {
                    tapFlags.didTapMinutesAction = true
                    onAddMinutes()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppTheme.accent.opacity(0.15), in: Capsule())
                .foregroundStyle(AppTheme.accent)
            } else {
                Chip(label: "No minutes", color: AppTheme.mutedText)
            }
        } else if let onOpenMinutes {
            Button("Minutes") {
                tapFlags.didTapMinutesAction = true
                onOpenMinutes()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(AppTheme.accent.opacity(0.15), in: Capsule())
            .foregroundStyle(AppTheme.accent)
        }
    }
}
