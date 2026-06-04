import SwiftUI
import SwiftData

struct MinutesListView: View {
    @Query(sort: \Minutes.meetingAt, order: .reverse) private var allMinutes: [Minutes]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedMinutes: Minutes?
    @State private var showingAdd = false
    @State private var projectFilter: Project? = nil

    private var filteredMinutes: [Minutes] {
        guard let proj = projectFilter else { return allMinutes }
        return allMinutes.filter { $0.projects.contains(where: { $0.id == proj.id }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            minutesTable
        }
        .navigationTitle("Minutes")
        .toolbar {
            ToolbarItem {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $selectedMinutes) { MinutesDetailView(minutes: $0, asSheet: true) }
        .sheet(isPresented: $showingAdd) { MinutesEditorSheet(minutes: nil, project: nil) }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Project", selection: $projectFilter) {
                Text("Any Project").tag(Optional<Project>.none)
                ForEach(allProjects) { p in
                    Text(p.name).tag(Optional(p))
                }
            }
            .labelsHidden()
            .fixedSize()
            if projectFilter != nil {
                Button("Clear") { projectFilter = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    #if os(macOS)
    private var minutesTable: some View {
        Table(filteredMinutes) {
            TableColumn("Date") { minutes in
                Text(minutes.meetingAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                    .lineLimit(1)
                    .onTapGesture { selectedMinutes = minutes }
            }
            .width(160)
            TableColumn("Time") { minutes in
                Text(minutes.meetingAt, format: .dateTime.hour().minute())
                    .foregroundStyle(.secondary)
            }
            .width(70)
            TableColumn("Summary") { minutes in
                Text(minutes.summary ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .onTapGesture { selectedMinutes = minutes }
            }
            TableColumn("Projects") { minutes in
                Text(minutes.projects.map(\.name).joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(160)
            TableColumn("Attendees") { minutes in
                Text("\(minutes.attendees.count)")
                    .foregroundStyle(.secondary)
            }
            .width(80)
        }
    }
    #else
    private var minutesTable: some View {
        List(filteredMinutes) { minutes in
            VStack(alignment: .leading, spacing: 4) {
                Text(minutes.meetingAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                    .font(.subheadline.bold())
                if let s = minutes.summary, !s.isEmpty {
                    Text(s).foregroundStyle(.secondary).font(.callout).lineLimit(1)
                }
            }
            .onTapGesture { selectedMinutes = minutes }
        }
    }
    #endif
}
