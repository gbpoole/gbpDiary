import SwiftUI
import SwiftData

struct MinutesDetailView: View {
    @Bindable var minutes: Minutes
    var asSheet: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if asSheet {
            NavigationStack {
                coreContent
            }
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 500)
            #endif
        } else {
            coreContent
        }
    }

    @ViewBuilder private var coreContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                metadataSection
                attendeesSection
                projectsSection
                notesSection
            }
            .padding()
        }
        .navigationTitle(minutes.meetingAt.formatted(.dateTime.day().month(.wide).year()))
        .toolbar {
            if asSheet {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var metadataSection: some View {
        GroupBox("Meeting") {
            HStack {
                Label(minutes.meetingAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()),
                      systemImage: "calendar")
                Spacer()
            }
            TextField("Summary", text: Binding(
                get: { minutes.summary ?? "" },
                set: { minutes.summary = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.plain)
        }
    }

    private var attendeesSection: some View {
        GroupBox("Attendees (\(minutes.attendees.count))") {
            if minutes.attendees.isEmpty {
                Text("No attendees recorded.").foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(minutes.attendees) { person in
                        Chip(label: person.name, color: .purple)
                    }
                }
            }
        }
    }

    private var projectsSection: some View {
        GroupBox("Projects (\(minutes.projects.count))") {
            if minutes.projects.isEmpty {
                Text("No linked projects.").foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(minutes.projects) { project in
                        Chip(label: project.name, color: .blue)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        GroupBox {
            MarkdownEditorSection(
                text: Binding(
                    get: { minutes.minutesContent ?? "" },
                    set: { minutes.minutesContent = $0.isEmpty ? nil : $0 }
                ),
                label: "Notes",
                placeholder: "No minutes recorded.",
                minEditorHeight: 120,
                startEditing: asSheet
            )
        }
    }

}

struct MinutesEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let minutes: Minutes?
    let project: Project?

    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var meetingAt: Date = Date()
    @State private var summary = ""
    @State private var selectedProjects: Set<Project.ID> = []
    @State private var selectedAttendees: Set<Person.ID> = []

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Meeting date & time", selection: $meetingAt)
                TextField("One-line summary", text: $summary)

                Section("Projects") {
                    ForEach(allProjects) { p in
                        Toggle(p.name, isOn: Binding(
                            get: { selectedProjects.contains(p.id) },
                            set: { if $0 { selectedProjects.insert(p.id) } else { selectedProjects.remove(p.id) } }
                        ))
                    }
                }

                Section("Attendees") {
                    ForEach(allPeople) { p in
                        Toggle(p.name, isOn: Binding(
                            get: { selectedAttendees.contains(p.id) },
                            set: { if $0 { selectedAttendees.insert(p.id) } else { selectedAttendees.remove(p.id) } }
                        ))
                    }
                }
            }
            .navigationTitle(minutes == nil ? "New Meeting" : "Edit Meeting")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(minutes == nil ? "Add" : "Save") { save() }
                }
            }
        }
        .onAppear {
            if let m = minutes {
                meetingAt = m.meetingAt
                summary = m.summary ?? ""
                selectedProjects = Set(m.projects.map(\.id))
                selectedAttendees = Set(m.attendees.map(\.id))
            } else if let p = project {
                selectedProjects = [p.id]
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 400)
        #endif
    }

    private func save() {
        let m = minutes ?? {
            let new = Minutes(meetingAt: meetingAt)
            modelContext.insert(new)
            return new
        }()
        m.meetingAt = meetingAt
        m.summary = summary.isEmpty ? nil : summary
        m.projects = allProjects.filter { selectedProjects.contains($0.id) }
        m.attendees = allPeople.filter { selectedAttendees.contains($0.id) }
        m.updatedAt = Date()
        dismiss()
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }
            .reduce(0) { $0 + $1 + spacing }
        return CGSize(width: proposal.width ?? 0, height: max(0, height - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        var rows: [[LayoutSubviews.Element]] = [[]]
        var x: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && !rows.last!.isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(view)
            x += size.width + spacing
        }
        return rows
    }
}
