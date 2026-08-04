import SwiftUI
import SwiftData

// The email "workspace" for one diary day: a multi-select list where the user cleans (dismisses),
// files (assigns projects), and connects each email to a Person. Dismiss persists on the model and is
// undoable (banner + Show-dismissed → Undismiss). Person reconciliation reuses the calendar-attendee
// flow (ResolveAttendeeSheet). A sheet may use a List freely — unlike the diary's VStack sections.
struct EmailReviewSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let day: Date

    @Query(sort: \EmailMessage.date, order: .reverse) private var allEmails: [EmailMessage]
    @Query(sort: \Project.name) private var allProjects: [Project]

    @State private var showDismissed = false
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var reconciling: EmailMessage?
    @State private var showingBulkProjects = false
    @State private var bulkProjects: [Project] = []
    @State private var lastDismissed: [PersistentIdentifier] = []
    @State private var undoVisible = false

    private var dayEmails: [EmailMessage] {
        let cal = Calendar.current
        return allEmails.filter { cal.isDate($0.date, inSameDayAs: day) && (showDismissed || !$0.dismissed) }
    }

    private var selectedEmails: [EmailMessage] {
        dayEmails.filter { selection.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlBar
                Divider()
                if dayEmails.isEmpty {
                    Text(showDismissed ? "No email for this day." : "No active email — everything is dismissed.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selection) {
                        ForEach(dayEmails, id: \.persistentModelID) { email in
                            EmailReviewRow(email: email, allProjects: allProjects,
                                           makeProject: makeProject,
                                           onReconcile: { reconciling = email })
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { if undoVisible { undoBar } }
            .navigationTitle("Review Email — \(day.formatted(date: .abbreviated, time: .omitted))")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $reconciling) { email in
                ResolveAttendeeSheet(
                    attendee: CalendarAttendee(name: email.fromName ?? "", email: email.fromAddress),
                    onResolve: { resolvePerson(email, $0) }
                )
            }
            .sheet(isPresented: $showingBulkProjects) { bulkProjectSheet }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 480)
        #endif
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            Toggle("Show dismissed", isOn: $showDismissed)
                #if os(macOS)
                .toggleStyle(.checkbox)
                #endif
            Spacer()
            if !selection.isEmpty {
                Text("\(selection.count) selected").font(.caption).foregroundStyle(.secondary)
                if selectedEmails.contains(where: { !$0.dismissed }) {
                    Button("Dismiss") { dismissSelected() }
                }
                if selectedEmails.contains(where: { $0.dismissed }) {
                    Button("Undismiss") { undismissSelected() }
                }
                Button("Assign project…") { bulkProjects = []; showingBulkProjects = true }
                Button("Clear") { selection.removeAll() }
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private var undoBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle")
            Text("Dismissed \(lastDismissed.count) message\(lastDismissed.count == 1 ? "" : "s")")
            Button("Undo") { undoDismiss() }
            Spacer()
            Button { undoVisible = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.thinMaterial)
    }

    // MARK: - Bulk project sheet

    private var bulkProjectSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Assign these projects to \(selection.count) email\(selection.count == 1 ? "" : "s"). Existing projects are kept.")
                    .font(.callout).foregroundStyle(.secondary)
                FuzzyPickerField(
                    allItems: allProjects,
                    selected: $bulkProjects,
                    label: \.name,
                    chipColor: AppTheme.project,
                    onCreateItem: { makeProject($0) },
                    tapArea: true,
                    emptyLabel: "Tap to choose or add projects"
                )
                Spacer()
            }
            .padding()
            .navigationTitle("Assign Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingBulkProjects = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Assign") { assignBulkProjects() }.disabled(bulkProjects.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 260)
        #endif
    }

    // MARK: - Actions

    private func dismissSelected() {
        let targets = selectedEmails.filter { !$0.dismissed }
        guard !targets.isEmpty else { return }
        for e in targets { e.dismissed = true }
        lastDismissed = targets.map { $0.persistentModelID }
        selection.removeAll()
        undoVisible = true
    }

    private func undismissSelected() {
        for e in selectedEmails where e.dismissed { e.dismissed = false }
        selection.removeAll()
    }

    private func undoDismiss() {
        for id in lastDismissed {
            if let e = allEmails.first(where: { $0.persistentModelID == id }) { e.dismissed = false }
        }
        lastDismissed = []
        undoVisible = false
    }

    private func assignBulkProjects() {
        for email in selectedEmails {
            for p in bulkProjects where !email.projects.contains(where: { $0.persistentModelID == p.persistentModelID }) {
                email.projects.append(p)
            }
        }
        showingBulkProjects = false
        selection.removeAll()
    }

    // Mirrors MinutesDetailView.resolveAttendee: link → add the address to that Person; create → new Person.
    private func resolvePerson(_ email: EmailMessage, _ result: AttendeeReconcileResult) {
        switch result {
        case .link(let p):
            if !email.fromAddress.isEmpty { p.emails = Person.appendingEmail(email.fromAddress, to: p.emails) }
            p.updatedAt = Date()
            email.person = p
        case .create(let name, let inst):
            let p = Person(name: name)
            if !email.fromAddress.isEmpty { p.emails = [email.fromAddress] }
            p.institution = inst
            modelContext.insert(p)
            email.person = p
        }
    }

    private func makeProject(_ name: String) -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let project = Project(name: trimmed)
        modelContext.insert(project)
        return project
    }
}

// One selectable email in the review list: direction, sender/subject/time, a person chip (tap to
// link/create), and an inline project picker. Dismissed rows show a gray marker.
private struct EmailReviewRow: View {
    let email: EmailMessage
    let allProjects: [Project]
    let makeProject: (String) -> Project?
    let onReconcile: () -> Void

    @State private var mailService = MailScriptService()
    @State private var openError: String?

    private var sender: String {
        if let name = email.fromName, !name.isEmpty { return name }
        return email.fromAddress.isEmpty ? "Unknown sender" : email.fromAddress
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { openInMail() } label: {
                Image(systemName: email.direction == .sent ? "paperplane" : "envelope")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help("Open in Mail")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(sender).lineLimit(1).fontWeight(.medium)
                    if email.direction == .sent { Chip(label: "Sent", color: .gray) }
                    if email.dismissed { Chip(label: "Dismissed", color: .gray) }
                    Spacer(minLength: 0)
                    Text(email.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                EmailContentLine(subject: email.subject, summary: email.summary,
                                 isSummarizing: email.summaryState == EmailSummaryState.pending.rawValue,
                                 font: .caption, lineLimit: 3)
                HStack(spacing: 10) {
                    personChip
                    projectPicker
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Regenerate summary", systemImage: "sparkles") {
                email.summary = nil
                email.summaryState = EmailSummaryState.pending.rawValue
            }
        }
        .alert("Couldn't open email", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(openError ?? "") }
    }

    private func openInMail() {
        mailService.openMessage(email) { result in
            if case .failure(let error) = result { openError = error.userMessage }
        }
    }

    @ViewBuilder private var personChip: some View {
        Button(action: onReconcile) {
            if let person = email.person {
                Chip(label: person.name, color: AppTheme.person)
            } else {
                Chip(label: "Unrecognized", color: AppTheme.warning)
            }
        }
        .buttonStyle(.plain)
        .help(email.person == nil
              ? "Unrecognized — click to link an existing person or create a new one"
              : "Linked person — click to change")
    }

    private var projectPicker: some View {
        FuzzyPickerField(
            allItems: allProjects,
            selected: Binding(get: { email.projects }, set: { email.projects = $0 }),
            label: \.name,
            chipColor: AppTheme.project,
            onCreateItem: makeProject,
            tapArea: true,
            emptyLabel: "Projects…"
        )
    }
}
