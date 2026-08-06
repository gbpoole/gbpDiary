import SwiftUI
import SwiftData

// The email triage workspace: a rolling last-3-days list segmented by triage state
// (To triage / Accepted / Dismissed). Each row has quick accept/dismiss/unclassify icons, opens in
// Mail, files projects (with tap-to-apply suggestions), reconciles the person, and can exclude the
// sender. A Refresh button fetches new mail since the last fetch.
struct EmailTriageSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \EmailMessage.date, order: .reverse) private var allEmails: [EmailMessage]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query private var allPeople: [Person]

    @State private var filter: EmailTriageState = .unclassified
    @State private var reconciling: EmailMessage?
    @State private var makingTodoFor: EmailMessage?
    @State private var service = MailScriptService()
    @State private var isFetching = false
    @State private var status: String?

    private var windowStart: Date { EmailIngest.window().start }

    private var windowEmails: [EmailMessage] {
        allEmails.filter { $0.date >= windowStart && $0.triageState == filter }
    }

    private func count(_ state: EmailTriageState) -> Int {
        allEmails.filter { $0.date >= windowStart && $0.triageState == state }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlBar
                Divider()
                if windowEmails.isEmpty {
                    Text(emptyLabel).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(windowEmails, id: \.persistentModelID) { email in
                            EmailTriageRow(email: email, allProjects: allProjects,
                                           suggestions: suggestions(for: email),
                                           makeProject: makeProject,
                                           onApplySuggestion: { apply($0, to: email) },
                                           onReconcile: { reconciling = email },
                                           onExcludeAddress: { excludeSender(email, domain: false) },
                                           onExcludeDomain: { excludeSender(email, domain: true) },
                                           onMakeTodo: { makingTodoFor = email })
                        }
                    }
                }
            }
            .navigationTitle("Triage Email — last 3 days")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
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
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 520)
        #endif
    }

    private var emptyLabel: String {
        switch filter {
        case .unclassified: "Nothing to triage — you're all caught up."
        case .accepted:     "No accepted email in the last 3 days."
        case .dismissed:    "No dismissed email in the last 3 days."
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button { refresh() } label: {
                Label(isFetching ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isFetching)
            Picker("", selection: $filter) {
                ForEach(EmailTriageState.allCases, id: \.self) { s in
                    Text("\(s.label) (\(count(s)))").tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            Spacer()
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

    // Add an exclude rule (address or domain) — future-only — and dismiss this email now.
    private func excludeSender(_ email: EmailMessage, domain: Bool) {
        let opts = EmailExcludeMatching.suggestions(forAddress: email.fromAddress)
        let rule = domain ? opts.last : opts.first
        if let rule { EmailExcludeStore.add(rule) }
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

    @State private var mailService = MailScriptService()
    @State private var openError: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            triageIcons
            Button { openInMail() } label: {
                Image(systemName: email.direction == .sent ? "paperplane" : "envelope")
                    .foregroundStyle(.secondary).font(.system(size: 13)).frame(width: 18)
            }
            .buttonStyle(.plain).help("Open in Mail")
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    personChip
                    suggestionChips
                    projectPicker
                    Text(email.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                EmailContentLine(subject: email.subject, summary: email.summary,
                                 isSummarizing: email.summaryState == EmailSummaryState.pending.rawValue)
            }
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button("Exclude sender (\(email.fromAddress))") { onExcludeAddress() }
            Button("Exclude domain") { onExcludeDomain() }
        }
        .alert("Couldn't open email", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(openError ?? "") }
    }

    // Move-to-state icons + "make todo": shows the actions that change the current state, plus a
    // create-todo action available in any state.
    @ViewBuilder private var triageIcons: some View {
        VStack(spacing: 6) {
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
        .frame(width: 22)
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

    // Suggested projects (before the picker): tap a chip to file the email under it. Never auto-applied.
    @ViewBuilder private var suggestionChips: some View {
        if !suggestions.isEmpty {
            Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(AppTheme.accent)
            ForEach(suggestions, id: \.id) { s in
                Button { onApplySuggestion(s) } label: {
                    Chip(label: "+ \(s.name)", color: AppTheme.project)
                }
                .buttonStyle(.plain)
                .help("Suggested — click to file under \(s.name)")
            }
        }
    }

    private var projectPicker: some View {
        FuzzyPickerField(
            allItems: allProjects,
            selected: Binding(get: { email.projects }, set: { email.projects = $0 }),
            label: \.name,
            chipColor: AppTheme.project,
            onCreateItem: makeProject,
            tapArea: true,
            emptyLabel: "None — tap to file under a project"
        )
    }
}
