import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct MinutesDetailView: View {
    @Bindable var minutes: Minutes
    var asSheet: Bool = false
    /// When true the sheet was opened for a brand-new meeting: Cancel deletes it,
    /// Escape deletes it, and the confirm button is labelled "Add" not "Done".
    var isNew: Bool = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]
    @Query private var allDocuments: [Document]
    @State private var summaryDraft = ""
    @State private var summaryDebouncer = Debouncer()
    @State private var durationText = ""
    @State private var durationError = false
    @FocusState private var customDurationFocused: Bool
    @Environment(WorkspaceModel.self) private var workspace
    @State private var showingDeleteConfirm = false
    @State private var isDeleted = false
    @State private var isConfirmed = false
    @State private var addingAction = false
    @State private var editingActionTask: Task?
    @State private var editingDocument: Document?
    @State private var lastAddedDocument: Document?
    @State private var showingLinkDoc = false
    @State private var minutesInsertion: MarkdownDocumentEditor.EditorInsertionRequest?
    #if os(macOS)
    // Calendar import (new meetings only): pick an event to populate the fields.
    @State private var calendarService = CalendarService()
    @State private var calendarAccess: CalendarAccess = .notDetermined
    @State private var calendarEvents: [CalendarEventDraft] = []
    @State private var importedEvent: CalendarEventDraft?
    // Scraped attendees that matched no existing Person — flagged for reconciliation, session-only.
    @State private var unresolvedAttendees: [CalendarAttendee] = []
    @State private var reconciling: CalendarAttendee?
    @State private var showingUnresolvedConfirm = false
    #endif

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
            // Metadata-only sheet. Bounded height + an inner ScrollView so a long attendee list
            // scrolls rather than pushing the Cancel/Add button bar off the bottom of the sheet.
            NavigationStack {
                coreContent
            }
            .frame(minWidth: 420, idealWidth: 460, maxWidth: 560, minHeight: 300, idealHeight: 480, maxHeight: 640)
        } else {
            coreContent
        }
    }

    @ViewBuilder private var coreContent: some View {
        Group {
            if asSheet {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        summaryField
                        metadataHeader
                    }
                    .padding()
                }
            } else {
                // Pin the summary + metadata header so it stays visible while the minutes scroll.
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 1) {
                            summaryField
                            Text(minutes.meetingAt.formatted(date: .complete, time: .shortened))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        metadataHeader
                    }
                    .padding([.horizontal, .top])
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.background)
                    // Pinned action bar (Add action / Add document / Download) — stays with the header.
                    DayActionBar(items: minutesActionItems)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            actionItemsSection
                            documentsSection
                            notesSection
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New Meeting" : "Edit Meeting")
        .toolbar {
            if asSheet {
                if isNew {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { performDelete(); dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                } else {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete") { showingDeleteConfirm = true }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Done") {
                        #if os(macOS)
                        if isNew && !unresolvedAttendees.isEmpty { showingUnresolvedConfirm = true; return }
                        #endif
                        confirmAdd()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .alert("Delete Meeting?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteMeeting() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the meeting and its minutes.")
        }
        .sheet(isPresented: $addingAction) {
            TaskEditorSheet(task: nil, defaultDate: minutes.meetingAt,
                            onTaskCreated: { insertActionLine(for: $0) },
                            presetProject: minutes.projects.first, originMinutes: minutes,
                            attendees: minutes.attendees, requireAssignee: true)
        }
        .sheet(item: $editingActionTask) { task in
            TaskEditorSheet(task: task, defaultDate: minutes.meetingAt,
                            attendees: minutes.attendees, requireAssignee: true)
        }
        .sheet(item: $editingDocument, onDismiss: { discardEmptyDocument() }) { doc in
            DocumentEditorSheet(document: doc, requireAttachment: true)
        }
        .sheet(isPresented: $showingLinkDoc) { documentLinkSheet }
        #if os(macOS)
        .alert("Unrecognized attendees", isPresented: $showingUnresolvedConfirm) {
            Button("Add anyway") { confirmAdd() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(unresolvedAttendees.count) attendee\(unresolvedAttendees.count == 1 ? " is" : "s are") unrecognized and won't be added. Continue?")
        }
        .sheet(item: $reconciling) { att in
            ResolveAttendeeSheet(attendee: att, onResolve: { resolveAttendee(att, with: $0) })
        }
        #endif
        .onAppear {
            ensureNoteExists()
            summaryDraft = minutes.summary ?? ""
            if let d = minutes.duration {
                let matchesPreset = durationPresets.contains { abs($0.hours - d.hoursNormalized) < 0.01 }
                durationText = matchesPreset ? "" : d.displayString
            }
            #if os(macOS)
            if isNew { setupCalendarImport() }
            #endif
        }
        #if os(macOS)
        .onChange(of: minutes.meetingAt) {
            if isNew && calendarAccess == .authorized { loadCalendarEvents() }
        }
        #endif
        .onDisappear {
            summaryDebouncer.cancel()
            // Never orphan-delete a meeting that's already open in a tab: confirmAdd opens the meeting's
            // tab before this sheet finishes dismissing, and that tab switch can reset the sheet's
            // @State (isConfirmed) — deleting a confirmed, now-displayed meeting would crash its tab.
            if isNew && !isConfirmed && !isDeleted && !workspace.references(minutes.persistentModelID) {
                // Escaped or dismissed without confirming — remove the orphan record.
                performDelete()
            } else if !isDeleted {
                minutes.summary = summaryDraft.isEmpty ? nil : summaryDraft
            }
        }
    }

    private func ensureNoteExists() {
        guard minutes.note == nil else { return }
        // Migrate legacy plain-text minutes if present, otherwise start an empty markdown note
        // so the minutes editor is always available in the meeting tab.
        let legacy = minutes.minutesContent ?? ""
        let note = Note(content: legacy)
        modelContext.insert(note)
        minutes.note = note
        minutes.minutesContent = nil
        minutes.updatedAt = Date()
    }

    private func performDelete() {
        guard !isDeleted else { return }
        isDeleted = true
        summaryDebouncer.cancel()
        // Close any open tab for this meeting, then detach and delete its note.
        workspace.closeEntity(minutes.persistentModelID)
        let note = minutes.note
        minutes.note = nil
        if let note {
            modelContext.delete(note)
        }
        let minutesId = minutes.id
        if let entries = try? modelContext.fetch(FetchDescriptor<DayEntry>()) {
            for entry in entries where entry.minutes?.id == minutesId {
                modelContext.delete(entry)
            }
        }
        modelContext.delete(minutes)
    }

    private func deleteMeeting() {
        performDelete()
        dismiss()
    }

    // Confirm the meeting: a new one opens in its own tab, ready to edit the minutes.
    private func confirmAdd() {
        isConfirmed = true
        if isNew { workspace.openMinutesForEditing(minutes.persistentModelID) }
        dismiss()
    }

    // Prominent title field.
    private var summaryField: some View {
        TextField("Meeting summary", text: $summaryDraft)
            .textFieldStyle(.plain)
            .font(.title2.weight(.semibold))
            .onChange(of: summaryDraft) { _, newValue in
                summaryDebouncer.schedule(delay: 1.0) {
                    minutes.summary = newValue.isEmpty ? nil : newValue
                    minutes.updatedAt = Date()
                }
            }
    }

    // Compact metadata block: projects, time, duration, attendees.
    private var metadataHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            #if os(macOS)
            if isNew { metaRow("Import") { importField } }
            #endif
            metaRow("Projects")  { projectsField }
            metaRow("Time")      { timeField }
            metaRow("Duration", alignment: .center) { durationPicker }
            metaRow("Attendees") { attendeesField }
            #if os(macOS)
            if isNew && !unresolvedAttendees.isEmpty {
                metaRow("Unrecognized") { unresolvedStrip }
            }
            #endif
        }
        .padding(10)
        .background(AppTheme.cardRaised.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metaRow<Content: View>(_ label: String,
                                        alignment: VerticalAlignment = .firstTextBaseline,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: alignment, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private var timeField: some View {
        DatePicker("", selection: $minutes.meetingAt, displayedComponents: [.hourAndMinute])
            .labelsHidden()
    }

    // A non-preset duration is currently set (shown highlighted in the custom chip).
    private var customIsActive: Bool {
        guard let d = minutes.duration else { return false }
        return !durationPresets.contains { abs($0.hours - d.hoursNormalized) < 0.01 }
    }

    // Lenient parse: accepts "2.5h"/"1d"/"1w", and a bare number ("2") as hours. nil if not usable.
    private func parseLooseDuration(_ text: String) -> Duration? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let d = Duration.parse(t) { return d }
        if let value = Double(t), value > 0 { return Duration(value: value, unit: .h) }
        return nil
    }

    private var durationPicker: some View {
        // The clear button flows right after the chips. Its vertical padding matches the chips so
        // it lines up, and the row's .center alignment keeps chips from shifting when it appears.
        FlowLayout(spacing: 6) {
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
            customChip
            if minutes.duration != nil {
                Button {
                    minutes.duration = nil
                    minutes.updatedAt = Date()
                    durationText = ""
                    durationError = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .help("Clear duration")
            }
        }
    }

    // Custom duration entered inline as a chip. Highlights when a non-preset value is active,
    // turns red on unparseable input (but tolerates a bare number as hours).
    private var customChip: some View {
        let fill: Color = durationError ? Color.red.opacity(0.18)
            : (customIsActive ? Color.accentColor : Color.secondary.opacity(0.12))
        let fg: Color = durationError ? .red : (customIsActive ? .white : .primary)
        return HStack(spacing: 3) {
            TextField("custom", text: $durationText)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(fg)
                .fixedSize()
                .focused($customDurationFocused)
                .onSubmit { customDurationFocused = false }
                .onChange(of: durationText) { _, newVal in
                    let trimmed = newVal.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        durationError = false
                    } else if let d = parseLooseDuration(trimmed) {
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
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(fill, in: Capsule())
    }

    private var attendeesField: some View {
        let projectFilters: [PickerFilter<Person>] = minutes.projects.map { project in
            PickerFilter(
                id: "project:\(project.id.uuidString)",
                label: project.name,
                chipColor: AppTheme.project,
                group: "Project"
            ) { person in
                project.devTeam.contains(where: { $0.id == person.id }) ||
                project.sciTeam.contains(where: { $0.id == person.id })
            }
        }
        var seen = Set<String>()
        let institutionFilters: [PickerFilter<Person>] = allPeople
            .compactMap(\.institution)
            .filter { seen.insert($0.id.uuidString).inserted }
            .sorted { $0.name < $1.name }
            .map { inst in
                PickerFilter(id: "inst:\(inst.id.uuidString)", label: inst.name, chipColor: AppTheme.institution, group: "Institution") {
                    $0.institution?.id == inst.id
                }
            }
        let allFilters = projectFilters + institutionFilters
        return FuzzyPickerField(
            allItems: allPeople,
            selected: Binding(
                get: { minutes.attendees },
                set: { minutes.attendees = $0; minutes.updatedAt = Date() }
            ),
            label: \.name,
            chipColor: AppTheme.person,
            onCreateItem: { makePerson($0) },
            tapArea: true,
            emptyLabel: "None selected — tap to add attendees",
            filters: allFilters.isEmpty ? nil : allFilters,
            defaultFilterId: projectFilters.first?.id
        )
    }

    // Create a new Person on the fly while picking attendees (auto-added to the selection).
    private func makePerson(_ name: String) -> Person? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let person = Person(name: trimmed)
        modelContext.insert(person)
        return person
    }

    private var projectsField: some View {
        FuzzyPickerField(
            allItems: allProjects,
            selected: Binding(
                get: { minutes.projects },
                set: { minutes.projects = $0; minutes.updatedAt = Date() }
            ),
            label: \.name,
            chipColor: AppTheme.project,
            onCreateItem: { makeProject($0) },
            tapArea: true,
            emptyLabel: "None selected — tap to link projects"
        )
    }

    // Create a new Project on the fly while linking one (auto-added to the selection).
    private func makeProject(_ projectName: String) -> Project? {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let project = Project(name: trimmed)
        modelContext.insert(project)
        return project
    }

    #if os(macOS)
    // MARK: - Calendar import (macOS, new meetings)

    // Reuses the standard FuzzyPickerField (search + filter chips) to choose a calendar event.
    // Per-calendar filtering is expressed as filter chips (none active → all calendars shown).
    @ViewBuilder private var importField: some View {
        switch calendarAccess {
        case .denied, .restricted, .writeOnly:
            Button("Enable calendar access…") { openCalendarSettings() }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(AppTheme.accent)
        case .notDetermined, .authorized:
            FuzzyPickerField(
                allItems: sortedImportEvents,
                selectedItem: $importedEvent,
                label: { importEventLabel($0) },
                chipColor: AppTheme.project,
                tapArea: true,
                emptyLabel: "Search calendar events…",
                filters: importCalendarFilters.isEmpty ? nil : importCalendarFilters,
                defaultActiveFilterIds: defaultCalendarFilterIds
            )
            .onChange(of: importedEvent) { _, ev in
                if let ev { applyImportedEvent(ev); importedEvent = nil }
            }
        }
    }

    private var sortedImportEvents: [CalendarEventDraft] {
        CalendarEventImport.sortedByProximity(calendarEvents, to: Date())
    }

    // Default calendar filters (from Settings) intersected with the calendars that actually have
    // events in the window, mapped to the picker's chip ids. Empty = show all.
    private var defaultCalendarFilterIds: Set<String> {
        let defaults = AppSettingsStore.defaultCalendarIDs
        guard !defaults.isEmpty else { return [] }
        let present = Set(calendarEvents.map { "cal:\($0.calendarId)" })
        return Set(defaults.map { "cal:\($0)" }).intersection(present)
    }

    // One filter chip per calendar that has events this day; none active = all calendars.
    private var importCalendarFilters: [PickerFilter<CalendarEventDraft>] {
        var seen = Set<String>()
        return calendarEvents
            .filter { !$0.calendarId.isEmpty && seen.insert($0.calendarId).inserted }
            .sorted { $0.calendarTitle.localizedCaseInsensitiveCompare($1.calendarTitle) == .orderedAscending }
            .map { ev in
                PickerFilter(id: "cal:\(ev.calendarId)", label: ev.calendarTitle, chipColor: AppTheme.project, group: "Calendar") {
                    $0.calendarId == ev.calendarId
                }
            }
    }

    private func importEventLabel(_ ev: CalendarEventDraft) -> String {
        let title = ev.title.isEmpty ? "Untitled" : ev.title
        // Title first, then the day/time (the picker spans several days, e.g. "Standup · Thu 30 Jul, 8:00 AM").
        let day = ev.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let when = ev.isAllDay ? "\(day), all day" : "\(day), \(ev.start.formatted(date: .omitted, time: .shortened))"
        return "\(title) · \(when)"
    }

    private func setupCalendarImport() {
        calendarAccess = calendarService.access
        switch calendarAccess {
        case .authorized:
            loadCalendarEvents()
        case .notDetermined:
            calendarService.requestAccess { granted in
                calendarAccess = granted
                if granted == .authorized { loadCalendarEvents() }
            }
        default:
            break
        }
    }

    private func loadCalendarEvents() {
        // A few days either side so you can import an event from a nearby day (e.g. catching up the
        // morning after, or a recurring event that only lands on certain weekdays). Proximity
        // ordering keeps the closest to now at the top.
        calendarEvents = calendarService.events(around: minutes.meetingAt, daysBefore: 3, daysAfter: 3)
    }

    // Populate the meeting from a chosen event; unmatched attendee People are created immediately
    // (the meeting already exists in the diary flow, so there is no deferred "Add" step).
    private func applyImportedEvent(_ ev: CalendarEventDraft) {
        let md = CalendarEventImport.minutesDraft(from: ev)
        if let summary = md.summary {
            summaryDraft = summary
            minutes.summary = summary
        }
        minutes.meetingAt = md.meetingAt
        minutes.duration = md.duration
        if let d = md.duration {
            let matchesPreset = durationPresets.contains { abs($0.hours - d.hoursNormalized) < 0.01 }
            durationText = matchesPreset ? "" : Self.cleanHours(d.hoursNormalized)
        } else {
            durationText = ""
        }
        let refs = allPeople.map { PersonRef(id: $0.id, name: $0.name, emails: $0.emails) }
        var attendees = minutes.attendees
        var unresolved: [CalendarAttendee] = []
        for resolution in AttendeeMatcher.resolve(attendees: ev.attendees, against: refs) {
            switch resolution {
            case .matched(let id):
                if let p = allPeople.first(where: { $0.id == id }),
                   !attendees.contains(where: { $0.id == p.id }) {
                    attendees.append(p)
                }
            case .create(let name, let email):
                // Do NOT auto-create — flag for the user to reconcile (link or create deliberately).
                unresolved.append(CalendarAttendee(name: name, email: email))
            }
        }
        minutes.attendees = attendees
        unresolvedAttendees = unresolved
        minutes.updatedAt = Date()
    }

    // MARK: - Attendee reconciliation

    private var unresolvedStrip: some View {
        FlowLayout(spacing: 6) {
            ForEach(unresolvedAttendees) { att in
                Button { reconciling = att } label: {
                    Chip(label: att.name.isEmpty ? (att.email ?? "?") : att.name, color: AppTheme.warning)
                }
                .buttonStyle(.plain)
                .help("Unrecognized — click to link to an existing person or create a new one")
            }
        }
    }

    private func resolveAttendee(_ att: CalendarAttendee, with result: AttendeeReconcileResult) {
        let person: Person
        switch result {
        case .link(let p):
            if let e = att.email, !e.isEmpty { p.emails = Person.appendingEmail(e, to: p.emails) }
            p.updatedAt = Date()
            person = p
        case .create(let name, let inst):
            let p = Person(name: name)
            if let e = att.email, !e.isEmpty { p.emails = [e] }
            p.institution = inst
            modelContext.insert(p)
            person = p
        }
        if !minutes.attendees.contains(where: { $0.id == person.id }) {
            minutes.attendees.append(person)
        }
        // Remove this entry, plus any other unresolved chip carrying the same email.
        unresolvedAttendees.removeAll { $0.id == att.id }
        if let e = att.email?.lowercased() {
            unresolvedAttendees.removeAll { $0.email?.lowercased() == e }
        }
        minutes.updatedAt = Date()
    }

    // Clean, round-trippable hours string (e.g. "1.5h", "0.25h", "1h") for the custom-duration field.
    private static func cleanHours(_ v: Double) -> String {
        if v == v.rounded() { return "\(Int(v))h" }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return "\(s)h"
    }

    private func openCalendarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Export (macOS)

    // Export the minutes as a portable file: a plain .md when there are no images or attached
    // documents, otherwise a .zip bundling the markdown + images/ and docs/ folders with the
    // markdown's image links rewritten to point at the bundled files.
    private func exportMinutes() {
        let base = MinutesExport.exportBaseName(summary: minutes.summary)
        let markdown = composedExportMarkdown()

        // Images referenced by the note (only those actually embedded).
        let referencedIDs = Set(AttachmentRef.referencedIDs(in: markdown))
        let images = (minutes.note?.attachments ?? []).filter { referencedIDs.contains($0.id) }
        // Attached documents' files.
        let docFiles: [Attachment] = minutes.documents.flatMap(\.attachments)
        let hasBundle = !images.isEmpty || !docFiles.isEmpty

        let panel = NSSavePanel()
        panel.nameFieldStringValue = hasBundle ? "\(base).zip" : "\(base).md"
        panel.allowedContentTypes = [hasBundle ? .zip : .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        do {
            if hasBundle {
                try exportBundle(markdown: markdown, base: base, images: images, docFiles: docFiles, to: dest)
            } else {
                try markdown.write(to: dest, atomically: true, encoding: .utf8)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // The shared header/action/document pieces for both markdown and PDF export.
    private func exportPieces() -> (title: String, dateLine: String, metaLines: [String],
                                    actionItems: [String], documents: [String]) {
        let dateLine = minutes.meetingAt.formatted(date: .complete, time: .shortened)
        var metaLines: [String] = []
        if !minutes.projects.isEmpty {
            metaLines.append("**Projects:** " + minutes.projects.map(\.name).joined(separator: ", "))
        }
        if let d = minutes.duration { metaLines.append("**Duration:** " + d.displayString) }
        if !minutes.attendees.isEmpty {
            metaLines.append("**Attendees:** " + minutes.attendees.map(\.name).joined(separator: ", "))
        }
        let actionItems = minutes.newTasks
            .sorted { $0.meetingTaskSortOrder < $1.meetingTaskSortOrder }
            .map { task -> String in
                var line = "\(task.summary) — \(task.assignee?.name ?? "Unassigned")"
                if let due = task.scheduledAt {
                    line += " (due \(due.formatted(date: .abbreviated, time: .omitted)))"
                }
                return line
            }
        let documents = minutes.documents.map { doc -> String in
            let name = documentTitle(doc)
            let n = doc.attachments.count
            return n > 0 ? "\(name) (\(n) file\(n == 1 ? "" : "s"))" : name
        }
        return (minutes.summary ?? "Meeting", dateLine, metaLines, actionItems, documents)
    }

    // Full export markdown: meeting header + Action Items + Documents + the minutes body.
    private func composedExportMarkdown() -> String {
        let p = exportPieces()
        return MinutesExport.composeMarkdown(
            title: p.title, dateLine: p.dateLine, metaLines: p.metaLines,
            actionItems: p.actionItems, documents: p.documents, body: minutes.note?.content ?? "")
    }

    // Export the minutes to PDF, honoring each image's manual display width and the selected page
    // palette. Composes a themed SwiftUI page (MinutesExportView) and renders it via
    // NSHostingView.dataWithPDF — synchronous and reliable (WKWebView stalls headless; ImageRenderer
    // drops Textual's async images). See MinutesExportView for why text/images are rendered as they are.
    private func exportPDF() {
        let base = MinutesExport.exportBaseName(summary: minutes.summary)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(base).pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        let p = exportPieces()
        let view = MinutesExportView(
            title: p.title, dateLine: p.dateLine, metaLines: p.metaLines,
            actionItems: p.actionItems, documents: p.documents,
            bodyMarkdown: minutes.note?.content ?? "",
            attachments: minutes.note?.attachments ?? [],
            palette: AppSettingsStore.pagePalette)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = .zero
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        let data = hosting.dataWithPDF(inside: hosting.bounds)
        do {
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try data.write(to: dest)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func exportBundle(markdown: String, base: String, images: [Attachment],
                              docFiles: [Attachment], to dest: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)/\(base)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work.deletingLastPathComponent()) }

        // Map each referenced image id → images/<uuid>.<ext>, copy the file, and rewrite the markdown.
        var relPaths: [UUID: String] = [:]
        if !images.isEmpty {
            let imagesDir = work.appendingPathComponent("images", isDirectory: true)
            try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            for att in images {
                let name = MinutesExport.bundleFileName(id: att.id, originalFileName: att.fileName)
                try? fm.copyItem(at: att.fileURL, to: imagesDir.appendingPathComponent(name))
                relPaths[att.id] = "images/\(name)"
            }
        }
        if !docFiles.isEmpty {
            let docsDir = work.appendingPathComponent("docs", isDirectory: true)
            try fm.createDirectory(at: docsDir, withIntermediateDirectories: true)
            for att in docFiles {
                try? fm.copyItem(at: att.fileURL, to: docsDir.appendingPathComponent(att.fileName))
            }
        }
        let rewritten = MinutesExport.rewriteImageLinks(markdown) { relPaths[$0] }
        try rewritten.write(to: work.appendingPathComponent("\(base).md"), atomically: true, encoding: .utf8)

        // Zip the folder via NSFileCoordinator's .forUploading (produces a temporary .zip).
        var coordError: NSError?
        var thrown: Error?
        NSFileCoordinator().coordinate(readingItemAt: work, options: [.forUploading], error: &coordError) { zipURL in
            do {
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.copyItem(at: zipURL, to: dest)
            } catch { thrown = error }
        }
        if let coordError { throw coordError }
        if let thrown { throw thrown }
    }
    #endif

    // Top action bar (macOS-agnostic; mirrors the diary page): add action item, add document, export.
    private var minutesActionItems: [DayActionItem] {
        var items: [DayActionItem] = [
            DayActionItem(id: "action", systemName: "checkmark.square", color: AppTheme.completed, tooltip: "Add action item") { addingAction = true },
            DayActionItem(id: "document", systemName: "doc.badge.plus", color: AppTheme.duration, tooltip: "Add document") { addDocument() },
        ]
        #if os(macOS)
        items.append(DayActionItem(id: "export", systemName: "square.and.arrow.down", color: AppTheme.accent, tooltip: "Download minutes") { exportMinutes() })
        items.append(DayActionItem(id: "export-pdf", systemName: "arrow.down.doc", color: AppTheme.accent, tooltip: "Download minutes as PDF") { exportPDF() })
        #endif
        return items
    }

    // Action items = the meeting's Tasks (Task.originMinutes); created via the top "Add action" button.
    private var actionItemsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                let items = minutes.newTasks.sorted { $0.meetingTaskSortOrder < $1.meetingTaskSortOrder }
                if items.isEmpty {
                    Text("No action items yet.")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 2)
                } else {
                    ForEach(items) { task in
                        MeetingActionRow(task: task, onOpen: { editingActionTask = task })
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Action Items").font(.caption).fontWeight(.semibold)
        }
    }

    // Add-document flow: create a document linked to the meeting and open its editor (where files are
    // added — a save requires at least one). If the editor is dismissed with no files, discard it.
    private func addDocument() {
        let doc = Document()
        if let proj = minutes.projects.first { doc.projects = [proj] }
        modelContext.insert(doc)
        minutes.documents.append(doc)
        minutes.updatedAt = Date()
        lastAddedDocument = doc
        editingDocument = doc
    }

    private func discardEmptyDocument() {
        guard let doc = lastAddedDocument else { return }
        lastAddedDocument = nil
        if doc.attachments.isEmpty {
            minutes.documents.removeAll { $0.id == doc.id }
            modelContext.delete(doc)
            minutes.updatedAt = Date()
        }
    }

    // When an action item is created, insert a bold "Action <INITIALS>: <summary>" on a new line at
    // the minutes cursor (bulleted to match the current line's list level); appends the due date.
    private func insertActionLine(for task: Task) {
        let initials = MinutesExport.initials(task.assignee?.name ?? "")
        let who = initials.isEmpty ? "" : "\(initials): "
        var text = "Action \(who)\(task.summary)"
        if let due = task.scheduledAt {
            text += " (due \(due.formatted(date: .abbreviated, time: .omitted)))"
        }
        minutesInsertion = .init(id: UUID(), text: "**\(text)**")
    }

    // Documents attached to the meeting (Minutes.documents ↔ Document.meetings). Link existing docs or
    // create a new one inline via the picker; rows open the document in a workspace tab.
    private var documentsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if minutes.documents.isEmpty {
                    Text("No documents attached.")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 2)
                } else {
                    ForEach(minutes.documents) { doc in
                        Button { workspace.focusOrOpen(.document(doc.persistentModelID)) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc").foregroundStyle(.secondary).font(.system(size: 13))
                                Text(documentTitle(doc)).lineLimit(1)
                                let n = doc.attachments.count
                                if n > 0 {
                                    Text("\(n) file\(n == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Link existing document…") { showingLinkDoc = true }
                    .font(.callout).foregroundStyle(AppTheme.accent).buttonStyle(.plain)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Documents").font(.caption).fontWeight(.semibold)
        }
    }

    // Link existing documents (from the document library) to the meeting — chips live in this sheet,
    // not the inline section.
    private var documentLinkSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Link existing documents to this meeting.")
                        .font(.callout).foregroundStyle(.secondary)
                    FuzzyPickerField(
                        allItems: allDocuments,
                        selected: Binding(
                            get: { minutes.documents },
                            set: { minutes.documents = $0; minutes.updatedAt = Date() }
                        ),
                        label: { documentTitle($0) },
                        chipColor: AppTheme.duration,
                        tapArea: true,
                        emptyLabel: "Tap to link documents"
                    )
                }
                .padding()
            }
            .navigationTitle("Link Documents")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showingLinkDoc = false } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 340)
        #endif
    }

    private func documentTitle(_ doc: Document) -> String {
        doc.summary?.isEmpty == false ? doc.summary! : "Untitled document"
    }

    private var notesSection: some View {
        GroupBox("Minutes") {
            if !isDeleted, let note = minutes.note {
                MarkdownDocumentEditor(
                    note: note,
                    startInEdit: workspace.autoEditMinutesId == minutes.persistentModelID,
                    onStartedEditing: { workspace.autoEditMinutesId = nil },
                    showsHeader: false,   // the meeting page header already shows project/tags
                    showsFormattingToolbar: true,
                    insertionRequest: minutesInsertion
                )
                .padding(.horizontal, -12)
            } else if !isDeleted {
                Button("Add minutes") {
                    let note = Note(content: "")
                    modelContext.insert(note)
                    minutes.note = note
                    minutes.updatedAt = Date()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppTheme.accent.opacity(0.15), in: Capsule())
                .foregroundStyle(AppTheme.accent)
            }
        }
    }

}

struct MinutesEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let minutes: Minutes?
    let project: Project?
    /// Date whose calendar day is used when creating a new meeting.
    /// Only the day portion is used; the time is set to the nearest quarter-hour.
    var presetDate: Date = Date()

    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query(sort: \Person.name) private var allPeople: [Person]

    @State private var meetingAt: Date = Date()
    @State private var summary = ""
    @State private var durationText = ""
    @State private var durationError = false
    @State private var selectedProjects: [Project] = []
    @State private var selectedAttendees: [Person] = []

    private var durationSection: some View {
        let presets: [(label: String, value: String)] = [
            ("15m", "0.25h"), ("30m", "0.5h"), ("1h", "1h"),
            ("1.5h", "1.5h"), ("2h", "2h"), ("3h", "3h")
        ]
        let parsedHours = Duration.parse(durationText.trimmingCharacters(in: .whitespaces))?.hoursNormalized
        return VStack(alignment: .leading, spacing: 8) {
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
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: durationText) { _, _ in durationError = false }
                if durationError {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                }
            }
        }
    }

    private var attendeesPicker: some View {
        let projectFilters: [PickerFilter<Person>] = selectedProjects.map { project in
            PickerFilter(
                id: "project:\(project.id.uuidString)",
                label: project.name,
                chipColor: AppTheme.project,
                group: "Project"
            ) { person in
                project.devTeam.contains(where: { $0.id == person.id }) ||
                project.sciTeam.contains(where: { $0.id == person.id })
            }
        }
        var seen = Set<String>()
        let institutionFilters: [PickerFilter<Person>] = allPeople
            .compactMap(\.institution)
            .filter { seen.insert($0.id.uuidString).inserted }
            .sorted { $0.name < $1.name }
            .map { inst in
                PickerFilter(id: "inst:\(inst.id.uuidString)", label: inst.name, chipColor: AppTheme.institution, group: "Institution") {
                    $0.institution?.id == inst.id
                }
            }
        let allFilters = projectFilters + institutionFilters
        return FuzzyPickerField(
            allItems: allPeople,
            selected: $selectedAttendees,
            label: \.name,
            chipColor: AppTheme.person,
            onCreateItem: { makePerson($0) },
            tapArea: true,
            emptyLabel: "None selected — tap to add attendees",
            filters: allFilters.isEmpty ? nil : allFilters,
            defaultFilterId: projectFilters.first?.id
        )
    }

    // Create a new Person on the fly while adding attendees (auto-added to the selection).
    private func makePerson(_ name: String) -> Person? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let person = Person(name: trimmed)
        modelContext.insert(person)
        return person
    }

    // Create a new Project on the fly while linking one (auto-added to the selection).
    private func makeProject(_ projectName: String) -> Project? {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let project = Project(name: trimmed)
        modelContext.insert(project)
        return project
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Summary") {
                        TextField("One-line summary", text: $summary)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: .infinity)
                    }
                    GroupBox("Duration") {
                        durationSection.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Projects") {
                        FuzzyPickerField(
                            allItems: allProjects,
                            selected: $selectedProjects,
                            label: \.name,
                            chipColor: AppTheme.project,
                            onCreateItem: { makeProject($0) },
                            tapArea: true,
                            emptyLabel: "None — tap to link projects"
                        )
                    }
                    GroupBox("Attendees") { attendeesPicker }
                    GroupBox("Date & Time") {
                        DatePicker("", selection: $meetingAt)
                            .labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle(minutes == nil ? "New Meeting" : "Edit Meeting")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(minutes == nil ? "Add" : "Save") { save() }
                        .keyboardShortcut(.defaultAction)
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
            } else {
                meetingAt = Self.nearestQuarterHourOn(presetDate)
                if let p = project { selectedProjects = [p] }
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

    /// Returns the nearest quarter-hour to the current clock time, placed on `date`'s calendar day.
    private static func nearestQuarterHourOn(_ date: Date) -> Date {
        let quarterHour = 15.0 * 60.0
        let rounded = (Date().timeIntervalSinceReferenceDate / quarterHour).rounded() * quarterHour
        let roundedNow = Date(timeIntervalSinceReferenceDate: rounded)
        let cal = Calendar.current
        let h = cal.component(.hour, from: roundedNow)
        let m = cal.component(.minute, from: roundedNow)
        return cal.date(bySettingHour: h, minute: m, second: 0, of: date) ?? date
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowAlignment: HorizontalAlignment = .leading
    // When true, items shorter than their row are centred vertically within it (default keeps the
    // legacy top-aligned behaviour so existing callers are unaffected).
    var centerVertically: Bool = false

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
                let itemY = centerVertically ? y + (rowHeight - size.height) / 2 : y
                view.place(at: CGPoint(x: x, y: itemY), proposal: ProposedViewSize(size))
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

// Compact action-item row for a meeting: status toggle + summary + assignee/date chips. The whole
// row (outside the status icon) opens the task editor; there is no separate edit icon.
private struct MeetingActionRow: View {
    @Bindable var task: Task
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            TaskStatusMenu(task: task) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.system(size: 16))
                    .frame(width: 20, height: 20)
            }

            Text(task.summary)
                .lineLimit(1)
                .strikethrough(task.status == .cancelled)
                .foregroundStyle(task.status == .cancelled ? AppTheme.mutedText : AppTheme.text)
            if let assignee = task.assignee {
                Chip(label: assignee.name, color: AppTheme.person)
            }
            if let due = task.scheduledAt {
                Chip(label: due.formatted(.dateTime.day().month()), color: AppTheme.duration)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .padding(.vertical, 3)
    }

    private var statusIcon: String {
        switch task.status {
        case .todo:            "circle"
        case .started:         "play.circle.fill"
        case .completed:       "checkmark.circle.fill"
        case .cancelled:       "xmark.circle.fill"
        case .followUpPending: "arrow.clockwise.circle.fill"
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .todo:            AppTheme.mutedText
        case .started:         AppTheme.started
        case .completed:       AppTheme.completed
        case .cancelled:       AppTheme.mutedText
        case .followUpPending: AppTheme.followUp
        }
    }

}
