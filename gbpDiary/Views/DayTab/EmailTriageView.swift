import SwiftUI
import SwiftData

// The central email triage page (sidebar "Triage"). Shows every fetched email across all days —
// segmented by triage bucket (To triage / Accepted / Tasks / Dismissed) with global counts and grouped
// under day headers — so a multi-day backlog is cleared in one place. Each row has quick
// accept/dismiss/unclassify icons, opens in Mail, files projects (with tap-to-apply suggestions),
// reconciles the person, and can exclude the sender. Refresh fetches new mail since the last fetch.
struct EmailTriageView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \EmailMessage.date, order: .reverse) private var allEmails: [EmailMessage]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query private var allPeople: [Person]

    @State private var filter: EmailTriageCategory = .toTriage
    @State private var reconciling: EmailMessage?
    @State private var makingTodoFor: EmailMessage?
    @State private var openingTask: Task?
    @State private var service = MailScriptService()
    @State private var isFetching = false
    @State private var status: String?

    private func emails(_ category: EmailTriageCategory) -> [EmailMessage] {
        allEmails.filter { EmailTriageCategory.classify(state: $0.triageState, hasTasks: $0.hasTasks) == category }
    }
    private func count(_ category: EmailTriageCategory) -> Int { emails(category).count }

    // The selected bucket's emails grouped by calendar day, most-recent day first (allEmails is
    // date-descending, so each day's rows stay latest-first and the day order is descending too).
    private var dayGroups: [(day: Date, emails: [EmailMessage])] {
        let cal = Calendar.current
        var order: [Date] = []
        var map: [Date: [EmailMessage]] = [:]
        for email in emails(filter) {
            let day = cal.startOfDay(for: email.date)
            if map[day] == nil { order.append(day); map[day] = [] }
            map[day]?.append(email)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            if dayGroups.isEmpty {
                Text(emptyLabel).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(dayGroups, id: \.day) { group in
                        Section {
                            ForEach(group.emails, id: \.persistentModelID) { email in
                                EmailTriageRow(email: email, allProjects: allProjects,
                                               suggestions: suggestions(for: email),
                                               makeProject: makeProject,
                                               onApplySuggestion: { apply($0, to: email) },
                                               onReconcile: { reconciling = email },
                                               onExcludeAddress: { excludeSender(email, domain: false) },
                                               onExcludeDomain: { excludeSender(email, domain: true) },
                                               onMakeTodo: { makingTodoFor = email },
                                               onOpenTask: { openingTask = email.tasks.first },
                                               onDeleteTasks: { deleteTasks(of: email) })
                            }
                        } header: {
                            Text(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                        }
                    }
                }
            }
        }
        .background(AppTheme.background)
        .sheet(item: $reconciling) { email in
            ResolveAttendeeSheet(
                attendee: CalendarAttendee(name: email.fromName ?? "", email: email.fromAddress),
                onResolve: { resolvePerson(email, $0) }
            )
        }
        .sheet(item: $makingTodoFor) { email in
            TaskEditorSheet(
                task: nil,
                defaultDate: email.date,
                onTaskCreated: { task in task.originEmail = email; email.accept() },
                presetProject: email.projects.first,
                presetSummary: email.subject.isEmpty ? nil : email.subject,
                presetNotes: email.summary
            )
        }
        .sheet(item: $openingTask) { task in
            TaskEditorSheet(task: task, defaultDate: task.originEmail?.date ?? Date())
        }
    }

    private var emptyLabel: String {
        switch filter {
        case .toTriage:  "Nothing to triage."
        case .accepted:  "No accepted email."
        case .tasks:     "No email to-dos."
        case .dismissed: "No dismissed email."
        }
    }

    private func deleteTasks(of email: EmailMessage) {
        for task in email.tasks { modelContext.delete(task) }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button { refresh() } label: {
                Label(isFetching ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isFetching)
            Picker("", selection: $filter) {
                ForEach(EmailTriageCategory.allCases, id: \.self) { c in
                    Text("\(c.label) (\(count(c)))").tag(c)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button { SettingsTab.open(SettingsTab.email) } label: {
                Label("Spam rules…", systemImage: "gearshape")
            }
            .help("Manage spam rules in Email settings")
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    // MARK: - Suggestions

    private func suggestions(for email: EmailMessage) -> [ProjectRef] {
        let projects = allProjects.map { ProjectRef(id: $0.id, name: $0.name) }
        let assigned = email.projects.map(\.id)
        let senderProjects = (email.person.map { $0.devProjects + $0.sciProjects } ?? []).map(\.id)
        let key = EmailThreading.threadKey(subject: email.subject,
                                           party: email.person?.id.uuidString ?? email.fromAddress)
        var prior: [UUID] = []
        for other in allEmails where other.id != email.id {
            let sameSender = !email.fromAddress.isEmpty
                && other.fromAddress.caseInsensitiveCompare(email.fromAddress) == .orderedSame
            let sameThread = EmailThreading.threadKey(subject: other.subject,
                                                      party: other.person?.id.uuidString ?? other.fromAddress) == key
            if sameSender || sameThread { prior.append(contentsOf: other.projects.map(\.id)) }
        }
        let input = EmailProjectSuggestions.Input(assignedIDs: assigned, senderProjectIDs: senderProjects,
                                                  priorProjectIDs: prior, aiSuggestedID: email.suggestedProjectID)
        return EmailProjectSuggestions.rank(input, projects: projects)
    }

    private func apply(_ ref: ProjectRef, to email: EmailMessage) {
        guard let project = allProjects.first(where: { $0.id == ref.id }),
              !email.projects.contains(where: { $0.id == project.id }) else { return }
        email.projects.append(project)
    }

    // MARK: - Refresh / exclude

    private func refresh() {
        let settings = EmailSettingsStore.load()
        guard settings.isConfigured, !isFetching else {
            if !settings.isConfigured { status = "Set your email account in Settings (⌘,)" }
            return
        }
        isFetching = true; status = nil
        let bounds = EmailIngest.fetchBounds(lastFetchedAt: EmailFetchStateStore.lastFetchedAt())
        service.fetchRange(rangeStart: bounds.start, rangeEnd: bounds.end, settings: settings) { result in
            isFetching = false
            switch result {
            case .success(let drafts):
                let added = EmailIngest.upsert(drafts, account: settings.accountName,
                                               existing: allEmails, people: allPeople, context: modelContext)
                EmailFetchStateStore.setLastFetchedAt(Date())
                status = added == 0 ? "Up to date" : "Fetched \(added) new"
            case .failure(let error):
                status = error.userMessage
            }
        }
    }

    // Add a sender spam rule (address or domain) — future-only — and dismiss this email now.
    private func excludeSender(_ email: EmailMessage, domain: Bool) {
        let opts = EmailExcludeMatching.suggestions(forAddress: email.fromAddress)
        if let rule = domain ? opts.last : opts.first { EmailExcludeStore.addSender(rule) }
        email.triageDismiss()
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

// One triage row: quick accept/dismiss/unclassify icons, open-in-Mail, sender/summary/time, a person
// chip (reconcile), project chips + inline picker, and tap-to-apply project suggestions.
private struct EmailTriageRow: View {
    @Bindable var email: EmailMessage
    let allProjects: [Project]
    let suggestions: [ProjectRef]
    let makeProject: (String) -> Project?
    let onApplySuggestion: (ProjectRef) -> Void
    let onReconcile: () -> Void
    let onExcludeAddress: () -> Void
    let onExcludeDomain: () -> Void
    let onMakeTodo: () -> Void
    let onOpenTask: () -> Void
    let onDeleteTasks: () -> Void

    @State private var mailService = MailScriptService()
    @State private var openError: String?
    @State private var editingProject = false
    @State private var confirmingDeleteTasks = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { openInMail() } label: {
                Image(systemName: email.direction == .sent ? "paperplane" : "envelope")
                    .foregroundStyle(.secondary).font(.system(size: 13)).frame(width: 18)
            }
            .buttonStyle(.plain).help("Open in Mail")
            VStack(alignment: .leading, spacing: 1) {
                // Person/project info and all the classification actions are grouped together on the
                // left (close to the info used to decide); only the send time trails on the right.
                HStack(spacing: 6) {
                    personChip
                    projectChip
                    todoChip
                    triageActions
                    Spacer(minLength: 8)
                    Text(email.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                EmailContentLine(subject: email.subject, summary: email.summary,
                                 isSummarizing: email.summaryState == EmailSummaryState.pending.rawValue)
            }
        }
        .padding(.vertical, 1)
        .contextMenu {
            EmailExperimentInChatButton(email: email)
            Button("Exclude sender (\(email.fromAddress))") { onExcludeAddress() }
            Button("Exclude domain") { onExcludeDomain() }
        }
        .alert("Couldn't open email", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(openError ?? "") }
        .alert("Delete \(email.tasks.count == 1 ? "to-do" : "to-dos")?", isPresented: $confirmingDeleteTasks) {
            Button("Delete", role: .destructive) { onDeleteTasks() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This deletes the to-do\(email.tasks.count == 1 ? "" : "s") made from this email. The email is kept.") }
    }

    // The email's linked-to-do status: opens the to-do (tap); context menu deletes it (undo make-todo).
    @ViewBuilder private var todoChip: some View {
        if email.hasTasks {
            let n = email.tasks.count
            EmailTodoChip(count: n, hasOpen: email.hasOpenTask, onOpen: onOpenTask)
                .contextMenu {
                    Button("Open to-do") { onOpenTask() }
                    Button(n == 1 ? "Delete to-do" : "Delete to-dos (\(n))", role: .destructive) {
                        confirmingDeleteTasks = true
                    }
                }
        }
    }

    // Move-to-state actions + "make todo", trailing the first line: only the actions that change the
    // current state show, plus a create-todo action available in any state.
    @ViewBuilder private var triageActions: some View {
        HStack(spacing: 8) {
            if email.triageState != .accepted {
                iconButton("checkmark.circle.fill", AppTheme.completed, "Accept") { email.accept() }
            }
            if email.triageState != .dismissed {
                iconButton("xmark.circle.fill", AppTheme.mutedText, "Dismiss") { email.triageDismiss() }
            }
            if email.triageState != .unclassified {
                iconButton("tray.full", AppTheme.accent, "Move back to triage") { email.unclassify() }
            }
            iconButton(email.tasks.isEmpty ? "checklist" : "checklist.checked", AppTheme.action,
                       email.tasks.isEmpty ? "Make a todo from this email" : "Make another todo (\(email.tasks.count) linked)",
                       onMakeTodo)
        }
    }

    private func iconButton(_ system: String, _ color: Color, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 15)).foregroundStyle(color)
        }
        .buttonStyle(.plain).help(help)
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
                let label = email.fromName?.isEmpty == false ? email.fromName!
                    : (email.fromAddress.isEmpty ? "Unrecognized" : email.fromAddress)
                Chip(label: label, color: AppTheme.warning)
            }
        }
        .buttonStyle(.plain)
        .help(email.person == nil ? "Unrecognized — click to link/create a person" : "Linked person — click to change")
    }

    // A single project chip. Assigned → the project (tap to edit). Not assigned but recommended →
    // "+ <Project>" (tap applies the recommendation; tap again to edit). Otherwise a neutral
    // "No Project" (tap to choose). Editing opens the standard project picker anchored to the chip.
    @ViewBuilder private var projectChip: some View {
        Button { projectTap() } label: {
            if let project = email.projects.first {
                Chip(label: project.name, color: AppTheme.project)
            } else if let rec = suggestions.first {
                Chip(label: "+ \(rec.name)", color: AppTheme.project)
            } else {
                Chip(label: "No Project", color: AppTheme.mutedText)
            }
        }
        .buttonStyle(.plain)
        .help(projectHelp)
        .overlay(alignment: .bottomLeading) {
            // Invisible anchor hosting the picker popover (driven by editingProject).
            FuzzyPickerField(
                allItems: allProjects,
                selected: Binding(get: { email.projects }, set: { email.projects = $0 }),
                label: \.name,
                chipColor: AppTheme.project,
                onCreateItem: makeProject,
                isPresented: $editingProject
            )
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .allowsHitTesting(false)
        }
    }

    private var projectHelp: String {
        if !email.projects.isEmpty { return "Project — click to change" }
        if suggestions.first != nil { return "Suggested project — click to apply (click again to change)" }
        return "No project — click to choose"
    }

    private func projectTap() {
        if email.projects.isEmpty, let rec = suggestions.first {
            onApplySuggestion(rec)      // first tap accepts the recommendation
        } else {
            editingProject = true       // choose / change / remove
        }
    }
}
