import SwiftUI
import SwiftData

struct MinutesListView: View {
    @Query(sort: \Minutes.meetingAt, order: .reverse) private var allMinutes: [Minutes]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedMinutes: Minutes?
    @State private var showingAdd = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedMinutes) {
                ForEach(allMinutes) { m in
                    MinutesRowView(minutes: m).tag(m)
                }
                .onDelete { offsets in
                    for i in offsets { modelContext.delete(allMinutes[i]) }
                }
            }
            .navigationTitle("Minutes")
            .toolbar {
                ToolbarItem {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
        } detail: {
            if let m = selectedMinutes {
                MinutesDetailView(minutes: m, asSheet: false)
            } else {
                ContentUnavailableView("Select a Meeting",
                                       systemImage: "calendar",
                                       description: Text("Choose a meeting from the sidebar."))
            }
        }
        .sheet(isPresented: $showingAdd) {
            MinutesEditorSheet(minutes: nil, project: nil)
        }
    }
}

private struct MinutesRowView: View {
    let minutes: Minutes
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(minutes.meetingAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                    .font(.subheadline.bold())
                Spacer()
                Text(minutes.meetingAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let s = minutes.summary, !s.isEmpty {
                Text(s).foregroundStyle(.secondary).font(.callout).lineLimit(1)
            }
            if !minutes.projects.isEmpty {
                HStack(spacing: 4) {
                    ForEach(minutes.projects) { p in
                        Chip(label: p.name, color: .blue)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
