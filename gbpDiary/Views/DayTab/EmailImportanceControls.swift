import SwiftUI

// Canonical colour for an email importance level (mirrors TaskTriageRow.priorityColor):
// High → destructive/red, Medium → follow-up/orange, Low → muted (never shown).
func emailImportanceColor(_ importance: EmailImportance) -> Color {
    switch importance {
    case .high:   AppTheme.destructive
    case .medium: AppTheme.followUp
    case .low:    AppTheme.mutedText
    }
}

// One-click importance toggle. Low is the neutral baseline, so only M / H are offered; tapping the
// active level again clears back to Low. Cloned from TaskTriageRow.priorityPicker. Closure-based so it
// serves both a single email and a whole thread (which writes every message).
struct EmailImportancePicker: View {
    let importance: EmailImportance
    let onSet: (EmailImportance) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach([EmailImportance.medium, .high], id: \.self) { level in
                let active = importance == level
                Button { onSet(active ? .low : level) } label: {
                    Text(level.short)
                        .font(.caption2.weight(.semibold))
                        .frame(minWidth: 15)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(active ? emailImportanceColor(level).opacity(0.22) : Color.secondary.opacity(0.10),
                                    in: Capsule())
                        .foregroundStyle(active ? emailImportanceColor(level) : AppTheme.mutedText)
                        .overlay(active ? Capsule().stroke(emailImportanceColor(level).opacity(0.75), lineWidth: 1) : nil)
                }
                .buttonStyle(.plain)
                .help("Importance \(level.displayName)")
            }
        }
    }
}

// Read-only importance chip — rendered only for Medium/High (Low is neutral and shows nothing).
struct EmailImportanceChip: View {
    let importance: EmailImportance

    var body: some View {
        if importance != .low {
            Chip(label: importance.short, color: emailImportanceColor(importance))
        }
    }
}
