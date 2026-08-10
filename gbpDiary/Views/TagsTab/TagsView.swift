import SwiftUI
import SwiftData

struct TagEntry: Identifiable {
    let tag: String
    var id: String { tag }
    let projects: [Project]
    let people: [Person]
    let notes: [Note]
}

struct TagsView: View {
    @Query(sort: \Project.name) private var projects: [Project]
    @Query(sort: \Person.name) private var people: [Person]
    @Query private var notes: [Note]

    @State private var selectedEntry: TagEntry?
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\TagEntry.tag)]

    private var tagEntries: [TagEntry] {
        var tagProjects: [String: [Project]] = [:]
        var tagPeople: [String: [Person]] = [:]
        var tagNotes: [String: [Note]] = [:]
        for project in projects {
            for tag in project.tags { tagProjects[tag, default: []].append(project) }
        }
        for person in people {
            for tag in person.tags { tagPeople[tag, default: []].append(person) }
        }
        for note in notes {
            for tag in note.tags { tagNotes[tag, default: []].append(note) }
        }
        let allTags = Set(tagProjects.keys).union(tagPeople.keys).union(tagNotes.keys).sorted()
        return allTags.map {
            TagEntry(tag: $0, projects: tagProjects[$0] ?? [], people: tagPeople[$0] ?? [], notes: tagNotes[$0] ?? [])
        }
    }

    private var rows: [TagEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let searched = query.isEmpty ? tagEntries : tagEntries.filter { FuzzyMatch.matches(query, in: $0.tag) }
        return searched.sorted(using: sortOrder)
    }

    // Tags have no discrete filter dimension — the toolbar collapses to search-only (Light tier).
    @State private var activeFilterIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            ListToolbar<TagEntry>(
                searchText: $searchText,
                searchPrompt: "Search tags…",
                activeFilterIds: $activeFilterIds
            )
            Divider()
            tagTable
        }
        .navigationTitle("Tags")
        .sheet(item: $selectedEntry) { TagDetailSheet(entry: $0) }
    }

    #if os(macOS)
    private var tagTable: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("Tag", value: \.tag) { entry in
                Text(entry.tag)
                    .font(AppTheme.bodyFont(size: 13))
                    .foregroundStyle(AppTheme.tag)
            }
            .width(min: 160, ideal: 260)
            TableColumn("Projects", value: \.projects.count) { entry in
                Text("\(entry.projects.count)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(min: 60, ideal: 70)
            TableColumn("People", value: \.people.count) { entry in
                Text("\(entry.people.count)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(min: 60, ideal: 70)
            TableColumn("Notes", value: \.notes.count) { entry in
                Text("\(entry.notes.count)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .width(min: 60, ideal: 70)
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .onTableRowDoubleClick { selectedEntry = rows[$0] }
    }
    #else
    private var tagTable: some View {
        List(rows) { entry in
            HStack {
                Text(entry.tag)
                Spacer()
                Text("\(entry.projects.count + entry.people.count + entry.notes.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .onTapGesture { selectedEntry = entry }
        }
    }
    #endif
}

struct TagDetailSheet: View {
    let entry: TagEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !entry.projects.isEmpty {
                        GroupBox("Projects (\(entry.projects.count))") {
                            FlowLayout(spacing: 6) {
                                ForEach(entry.projects) { project in
                                    Chip(label: project.name, color: AppTheme.project)
                                }
                            }
                        }
                    }
                    if !entry.people.isEmpty {
                        GroupBox("People (\(entry.people.count))") {
                            FlowLayout(spacing: 6) {
                                ForEach(entry.people) { person in
                                    Chip(label: person.name, color: AppTheme.person)
                                }
                            }
                        }
                    }
                    if !entry.notes.isEmpty {
                        GroupBox("Notes (\(entry.notes.count))") {
                            FlowLayout(spacing: 6) {
                                ForEach(entry.notes) { note in
                                    let snippet = noteSnippet(note)
                                    Chip(label: snippet, color: AppTheme.tag)
                                }
                            }
                        }
                    }
                    if entry.projects.isEmpty && entry.people.isEmpty && entry.notes.isEmpty {
                        Text("Nothing uses this tag.").foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("#\(entry.tag)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 300)
        #endif
    }

    private func noteSnippet(_ note: Note) -> String {
        if let date = note.dayRecord?.date {
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
        for rawLine in note.content.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { return String(line.prefix(40)) }
        }
        return "Note"
    }
}
