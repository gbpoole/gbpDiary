import SwiftUI
import SwiftData

struct MinutesDetailView: View {
    @Bindable var minutes: Minutes
    var asSheet: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]
    @State private var durationText = ""
    @State private var durationError = false

    private struct DurationPreset: Identifiable {
        let id: String
        let label: String
        let hours: Double
    }
    private let durationPresets: [DurationPreset] = [
        DurationPreset(id: "15m",  label: "15m",  hours: 0.25),
        DurationPreset(id: "30m",  label: "30m",  hours: 0.5),
        DurationPreset(id: "1h",   label: "1h",   hours: 1.0),
        DurationPreset(id: "1.5h", label: "1.5h", hours: 1.5),
        DurationPreset(id: "2h",   label: "2h",   hours: 2.0),
        DurationPreset(id: "3h",   label: "3h",   hours: 3.0),
    ]
    private func isPresetActive(_ preset: DurationPreset) -> Bool {
        guard let d = minutes.duration else { return false }
        return abs(d.hoursNormalized - preset.hours) < 0.01
    }

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
                ToolbarItem(placement: .automatic) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            ensureNoteExists()
            if let d = minutes.duration {
                let matchesPreset = durationPresets.contains { abs($0.hours - d.hoursNormalized) < 0.01 }
                durationText = matchesPreset ? "" : d.displayString
            }
        }
    }

    private func ensureNoteExists() {
        guard minutes.note == nil else { return }
        let note = Note(content: minutes.minutesContent ?? "")
        modelContext.insert(note)
        minutes.note = note
        minutes.minutesContent = nil
        minutes.updatedAt = Date()
    }

    private var metadataSection: some View {
        GroupBox("Meeting") {
            DatePicker("Date & time", selection: $minutes.meetingAt)
            TextField("Summary", text: Binding(
                get: { minutes.summary ?? "" },
                set: { minutes.summary = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.plain)
            durationPicker
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(durationPresets) { preset in
                    Button(preset.label) {
                        minutes.duration = Duration(value: preset.hours, unit: .h)
                        minutes.updatedAt = Date()
                        durationText = ""
                        durationError = false
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isPresetActive(preset) ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(isPresetActive(preset) ? Color.white : Color.primary)
                }
            }
            HStack(spacing: 6) {
                TextField("Custom (e.g. 2.5h)", text: $durationText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onChange(of: durationText) { _, newVal in
                        let trimmed = newVal.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty {
                            durationError = false
                        } else if let d = Duration.parse(trimmed) {
                            durationError = false
                            minutes.duration = d
                            minutes.updatedAt = Date()
                        } else {
                            durationError = true
                        }
                    }
                if durationError {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                if minutes.duration != nil {
                    Button("Clear") {
                        minutes.duration = nil
                        minutes.updatedAt = Date()
                        durationText = ""
                        durationError = false
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var attendeesSection: some View {
        GroupBox("Attendees") {
            FuzzyPickerField(
                allItems: allPeople,
                selected: Binding(
                    get: { minutes.attendees },
                    set: { minutes.attendees = $0; minutes.updatedAt = Date() }
                ),
                label: \.name,
                chipColor: AppTheme.person
            )
        }
    }

    private var projectsSection: some View {
        GroupBox("Projects") {
            FuzzyPickerField(
                allItems: allProjects,
                selected: Binding(
                    get: { minutes.projects },
                    set: { minutes.projects = $0; minutes.updatedAt = Date() }
                ),
                label: \.name,
                chipColor: AppTheme.project
            )
        }
    }

    private var notesSection: some View {
        GroupBox("Notes") {
            if let note = minutes.note {
                NoteEditingArea(note: note)
                    .padding(.horizontal, -12)
            }
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

    @State private var meetingAt: Date = Self.nearestQuarterHour(from: Date())
    @State private var summary = ""
    @State private var durationText = ""
    @State private var durationError = false
    @State private var selectedProjects: [Project] = []
    @State private var selectedAttendees: [Person] = []

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Meeting date & time", selection: $meetingAt)
                TextField("One-line summary", text: $summary)

                Section("Duration") {
                    let presets: [(label: String, value: String)] = [
                        ("15m", "0.25h"), ("30m", "0.5h"), ("1h", "1h"),
                        ("1.5h", "1.5h"), ("2h", "2h"), ("3h", "3h")
                    ]
                    let parsedHours = Duration.parse(durationText.trimmingCharacters(in: .whitespaces))?.hoursNormalized
                    HStack(spacing: 6) {
                        ForEach(presets, id: \.label) { preset in
                            let active = parsedHours.map { abs($0 - (Duration.parse(preset.value)?.hoursNormalized ?? -1)) < 0.01 } ?? false
                            Button(preset.label) {
                                durationText = preset.value
                                durationError = false
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(active ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(active ? Color.white : Color.primary)
                        }
                    }
                    HStack {
                        TextField("Custom (e.g. 2.5h)", text: $durationText)
                            .onChange(of: durationText) { _, _ in durationError = false }
                        if durationError {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Projects") {
                    FuzzyPickerField(
                        allItems: allProjects,
                        selected: $selectedProjects,
                        label: \.name,
                        chipColor: AppTheme.project
                    )
                }

                Section("Attendees") {
                    FuzzyPickerField(
                        allItems: allPeople,
                        selected: $selectedAttendees,
                        label: \.name,
                        chipColor: AppTheme.person
                    )
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
                durationText = m.duration?.displayString ?? ""
                selectedProjects = m.projects
                selectedAttendees = m.attendees
            } else if let p = project {
                selectedProjects = [p]
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 400)
        #endif
    }

    private func save() {
        let trimmedDur = durationText.trimmingCharacters(in: .whitespaces)
        var parsedDuration: Duration? = nil
        if !trimmedDur.isEmpty {
            guard let d = Duration.parse(trimmedDur) else {
                durationError = true
                return
            }
            parsedDuration = d
        }

        let m = minutes ?? {
            let new = Minutes(meetingAt: meetingAt)
            modelContext.insert(new)
            return new
        }()
        m.meetingAt = meetingAt
        m.summary = summary.isEmpty ? nil : summary
        m.duration = parsedDuration
        m.projects = selectedProjects
        m.attendees = selectedAttendees
        m.updatedAt = Date()
        dismiss()
    }

    private static func nearestQuarterHour(from date: Date) -> Date {
        let quarterHour = 15.0 * 60.0
        let interval = date.timeIntervalSinceReferenceDate
        let rounded = (interval / quarterHour).rounded() * quarterHour
        return Date(timeIntervalSinceReferenceDate: rounded)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowAlignment: HorizontalAlignment = .leading

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
            let rowWidth = row.reduce(CGFloat(0)) { $0 + $1.sizeThatFits(.unspecified).width }
                + CGFloat(max(0, row.count - 1)) * spacing
            let startX: CGFloat = switch rowAlignment {
                case .center:   bounds.minX + (bounds.width - rowWidth) / 2
                case .trailing: bounds.maxX - rowWidth
                default:        bounds.minX
            }
            var x = startX
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
