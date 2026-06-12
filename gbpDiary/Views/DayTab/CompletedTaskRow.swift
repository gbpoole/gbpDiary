import SwiftUI

struct CompletedTaskRow: View {
    let task: Task
    var onEdit: (Task) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.completed)
                .font(.system(size: 15))

            Text(task.summary)
                .strikethrough()
                .foregroundStyle(AppTheme.mutedText)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let at = task.completedAt {
                Text(at, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(AppTheme.Kanagawa.overlay1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onEdit(task) }
    }
}
