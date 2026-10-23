import SwiftUI
import SwiftData

// The Minutes table's inline project editor: the project(s) render as pills in the cell, and clicking opens
// the app's shared `FuzzyPickerField` popover — same search, chips, filters and create-inline behaviour as
// every other project picker in the app.
//
// `tapArea: true` makes the whole cell the trigger and shows `emptyLabel` when nothing is set. The picker is
// a real `Button` + `.popover`, which is what makes it safe inside a `Table` cell — a bare tap gesture there
// fights NSTableView's own click handling (see the list-page rules in CLAUDE.md).
struct MinutesProjectCell: View {
    let minutes: Minutes
    /// All projects, name-sorted — supplied by the list view's existing `@Query` so this doesn't re-query.
    let allProjects: [Project]

    var body: some View {
        FuzzyPickerField(
            allItems: candidates,
            selected: projectsBinding,
            label: \.name,
            chipColor: AppTheme.project,
            placeholder: "Search projects…",
            onCreateItem: { name in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let project = Project(name: trimmed)
                minutes.modelContext?.insert(project)
                return project
            },
            tapArea: true,
            emptyLabel: MeetingProjectOptions.emptyLabel
        )
    }

    /// Writes go through the model so `updatedAt` is stamped, as every other metadata edit does.
    private var projectsBinding: Binding<[Project]> {
        Binding(
            get: { minutes.projects },
            set: {
                minutes.projects = $0
                minutes.updatedAt = Date()
            }
        )
    }

    /// Offer order: projects this meeting's attendees work on first, then everything else; the picker's
    /// own search covers the rest.
    private var candidates: [Project] {
        let ordered = MeetingProjectOptions.candidates(
            selectedIDs: minutes.projects.map(\.id),
            attendeeProjectIDs: attendeeProjectIDs,
            all: allProjects.map { .init(id: $0.id, name: $0.name) },
            completedIDs: Set(allProjects.filter(\.isCompleted).map(\.id))
        )
        let byID = Dictionary(allProjects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return ordered.compactMap { byID[$0.id] }
    }

    private var attendeeProjectIDs: [UUID] {
        var seen = Set<UUID>()
        var ids: [UUID] = []
        for person in minutes.attendees {
            for project in person.teamProjects where seen.insert(project.id).inserted {
                ids.append(project.id)
            }
        }
        return ids
    }
}
