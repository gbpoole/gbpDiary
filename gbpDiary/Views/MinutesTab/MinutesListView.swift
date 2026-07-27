import SwiftUI
import SwiftData

struct MinutesListView: View {
    @Query(sort: \Minutes.meetingAt, order: .reverse) private var allMinutes: [Minutes]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace

    @State private var editingMinutes: Minutes?
    @State private var showingAdd = false
    @State private var activeFilterIds: Set<String> = []

    private var minutesFilters: [PickerFilter<Minutes>] {
        let projectGroup = allProjects.map { p in
            PickerFilter<Minutes>(id: "project.\(p.id)", label: p.name, chipColor: AppTheme.project, group: "Project") {
                $0.projects.contains(where: { $0.id == p.id })
            }
        }
        let attendeeGroup = allPeople.map { person in
            PickerFilter<Minutes>(id: "attendee.\(person.id)", label: person.name, chipColor: AppTheme.person, group: "Attendee") {
                $0.attendees.contains(where: { $0.id == person.id })
            }
        }
        return projectGroup + attendeeGroup
    }

    private var filteredMinutes: [Minutes] {
        FilterEngine.apply(allMinutes, filters: minutesFilters, activeIds: activeFilterIds)
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(
                filters: minutesFilters,
                activeFilterIds: $activeFilterIds,
                onClearAll: { activeFilterIds = [] }
            )
            Divider()
            minutesTable
        }
        .navigationTitle("Minutes")
        .toolbar {
            ToolbarItem {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editingMinutes) { MinutesDetailView(minutes: $0, asSheet: true).presentationSizing(.fitted) }
        .sheet(isPresented: $showingAdd) { MinutesEditorSheet(minutes: nil, project: nil) }
    }

    private func openInspector(for minutes: Minutes) {
        workspace.openInNewTab(.minutes(minutes.persistentModelID))
    }

    #if os(macOS)
    private var minutesTable: some View {
        Table(filteredMinutes) {
            TableColumn("Date") { minutes in
                Text(minutes.meetingAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                    .lineLimit(1)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.text)
                    .onTapGesture { openInspector(for: minutes) }
                    .contextMenu { editMenuItem(minutes) }
            }
            .width(160)
            TableColumn("Time") { minutes in
                Text(minutes.meetingAt, format: .dateTime.hour().minute())
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(70)
            TableColumn("Summary") { minutes in
                Text(minutes.summary ?? "")
                    .foregroundStyle(AppTheme.text)
                    .lineLimit(1)
                    .onTapGesture { openInspector(for: minutes) }
                    .contextMenu { editMenuItem(minutes) }
            }
            TableColumn("Projects") { minutes in
                Text(minutes.projects.map(\.name).joined(separator: ", "))
                    .foregroundStyle(AppTheme.project)
                    .lineLimit(1)
            }
            .width(160)
            TableColumn("Attendees") { minutes in
                Text("\(minutes.attendees.count)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(80)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
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
            .onTapGesture { openInspector(for: minutes) }
            .contextMenu { editMenuItem(minutes) }
        }
    }
    #endif

    @ViewBuilder
    private func editMenuItem(_ minutes: Minutes) -> some View {
        Button("Edit meeting info…") { editingMinutes = minutes }
    }
}
