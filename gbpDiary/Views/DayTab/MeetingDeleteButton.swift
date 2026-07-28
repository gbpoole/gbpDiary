import SwiftUI
import SwiftData

// A trash-icon button for a meeting row on the diary. Confirms, then removes the day's meeting
// `DayEntry` and the linked `Minutes` (whose note cascades), and closes any workspace tab showing
// that meeting.
struct MeetingDeleteButton: View {
    let minutes: Minutes

    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace
    @State private var confirming = false

    var body: some View {
        Button { confirming = true } label: {
            Image(systemName: "trash").font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.action)
        .help("Delete meeting")
        .alert("Delete Meeting?", isPresented: $confirming) {
            Button("Delete", role: .destructive) { deleteMeeting() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the meeting and its minutes.")
        }
    }

    private func deleteMeeting() {
        let id = minutes.persistentModelID
        workspace.closeEntity(id)
        // Remove the diary meeting entry (if any) pointing at these minutes; nothing else references it.
        if let entries = try? modelContext.fetch(FetchDescriptor<DayEntry>()) {
            for entry in entries where entry.minutes?.persistentModelID == id {
                modelContext.delete(entry)
            }
        }
        modelContext.delete(minutes)
    }
}
