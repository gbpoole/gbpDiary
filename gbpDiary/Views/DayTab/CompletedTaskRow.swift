import SwiftUI

struct CompletedTaskRow: View {
    let task: Task
    var onEdit: (Task) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 15))

            Text(task.summary)
                .strikethrough()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let at = task.completedAt {
                Text(at, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onEdit(task) }
    }
}
