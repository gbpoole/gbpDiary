import SwiftUI

// A clickable provenance glyph for task rows: shows the source-kind icon and, on click, opens the source —
// the email in Mail (via `MailScriptService.openMessage`, the same path the task editor uses) or the deep
// link (slack/web) via `openURL`. Renders nothing when the task has no source.
struct SourceGlyphButton: View {
    let task: Task

    @Environment(\.openURL) private var openURL
    @State private var mailService = MailScriptService()

    private var kind: TaskSourceKind? {
        task.source?.kind ?? (task.originEmail != nil ? .email : nil)
    }

    var body: some View {
        if let kind {
            Button { open(kind) } label: {
                Image(systemName: kind.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open \(kind.displayName.lowercased()) source")
        }
    }

    private func open(_ kind: TaskSourceKind) {
        if kind == .email, let email = task.source?.email ?? task.originEmail {
            mailService.openMessage(email) { _ in }
            return
        }
        if let s = task.source?.url, let url = URL(string: s) { openURL(url) }
    }
}
