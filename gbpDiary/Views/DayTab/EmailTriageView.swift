import SwiftUI
import SwiftData

// The central email triage page (sidebar "Emails"). Shows every fetched conversation (the persistent
// `EmailConversation` entity — sent + received threaded across days) segmented by triage bucket
// (To triage / Accepted / Tasks / Dismissed) with global counts, each grouped under its latest-message
// day — so a multi-day backlog is cleared in one place. The conversation OWNS the cross-cutting state, so
// a single triage action (accept/dismiss, file the project, set importance, reconcile the person, log
// time, make-todo) applies to the whole conversation. Refresh fetches new mail since the last fetch.
struct EmailTriageView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \EmailMessage.date, order: .reverse) private var allEmails: [EmailMessage]
    @Query private var allConversations: [EmailConversation]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query private var allPeople: [Person]

    @State private var filter: EmailTriageCategory = .toTriage
    @State private var reconciling: EmailConversation?
    @State private var makingTodoFor: EmailConversation?
    @State private var openingTask: Task?
    @State private var service = MailScriptService()
    @State private var isFetching = false
    @State private var status: String?

    // Each conversation shown ONCE, grouped under its latest-message day, most-recent day first.
    private var allDayGroups: [(day: Date, conversations: [EmailConversation])] {
        let cal = Calendar.current
        var order: [Date] = []
        var byDay: [Date: [EmailConversation]] = [:]
        for convo in allConversations.sorted(by: { $0.date > $1.date }) where !convo.messages.isEmpty {
            let day = cal.startOfDay(for: convo.date)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(convo)
        }
        return order.map { ($0, byDay[$0] ?? []) }
    }

    private func category(of convo: EmailConversation) -> EmailTriageCategory {
        EmailTriageCategory.classify(state: convo.triageState, hasTasks: convo.taskCount > 0)
    }

    // The selected bucket's conversations, grouped by day. Days are most-recent first; within a day,
    // conversations run in ascending time (earliest → latest).
    private var dayGroups: [(day: Date, conversations: [EmailConversation])] {
        allDayGroups.compactMap { group in
            let convos = group.conversations
                .filter { category(of: $0) == filter }
                .sorted { $0.date < $1.date }
            return convos.isEmpty ? nil : (group.day, convos)
        }
    }

    private func count(_ category: EmailTriageCategory) -> Int {
        allDayGroups.reduce(0) { $0 + $1.conversations.filter { self.category(of: $0) == category }.count }
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
                            ForEach(group.conversations, id: \.persistentModelID) { convo in
                                EmailTriageConversationRow(
                                    conversation: convo, allProjects: allProjects,
                                    suggestions: suggestions(for: convo),
                                    makeProject: makeProject,
                                    onApplySuggestion: { apply($0, to: convo) },
                                    onReconcile: { reconciling = convo },
                                    onExcludeAddress: { excludeSender(convo, domain: false) },
                                    onExcludeDomain: { excludeSender(convo, domain: true) },
                                    onMakeTodo: { makingTodoFor = convo },
                                    onOpenTask: { openingTask = convo.tasks.first },
                                    onDeleteTasks: { deleteTasks(of: convo) })
                            }
                        } header: {
                            Text(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                        }
                    }
                }
            }
        }
        .background(AppTheme.background)
        .sheet(item: $reconciling) { convo in
            ResolveAttendeeSheet(
                attendee: CalendarAttendee(name: convo.fromName ?? "", email: convo.fromAddress),
                onResolve: { resolvePerson(convo, $0) }
            )
        }
        .sheet(item: $makingTodoFor) { convo in
            TaskEditorSheet(
                task: nil,
                defaultDate: convo.date,
                onTaskCreated: { task in task.originEmail = convo.latest; convo.accept() },
                presetProject: convo.projects.first,
                presetSummary: convo.displaySubject == "(no subject)" ? nil : convo.displaySubject,
                presetNotes: convo.latestMessageSummary
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

    // MARK: - Conversation actions

    private func deleteTasks(of convo: EmailConversation) {
        for task in convo.tasks { modelContext.delete(task) }
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

    private func suggestions(for convo: EmailConversation) -> [ProjectRef] {
        guard let latest = convo.latest else { return [] }
        let projects = allProjects.map { ProjectRef(id: $0.id, name: $0.name) }
        let assigned = convo.projects.map(\.id)
        let senderProjects = (convo.person.map { $0.devProjects + $0.sciProjects } ?? []).map(\.id)
        let address = convo.fromAddress
        var prior: [UUID] = []
        for other in allConversations where other.id != convo.id {
            let sameParty = !address.isEmpty
                && other.fromAddress.caseInsensitiveCompare(address) == .orderedSame
            if sameParty { prior.append(contentsOf: other.projects.map(\.id)) }
        }
        let input = EmailProjectSuggestions.Input(assignedIDs: assigned, senderProjectIDs: senderProjects,
                                                  priorProjectIDs: prior, aiSuggestedID: latest.suggestedProjectID)
        return EmailProjectSuggestions.rank(input, projects: projects)
    }

    // Apply a suggested project to the conversation (dedup).
    private func apply(_ ref: ProjectRef, to convo: EmailConversation) {
        guard let project = allProjects.first(where: { $0.id == ref.id }) else { return }
        if !convo.projects.contains(where: { $0.id == project.id }) { convo.projects.append(project) }
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

    // Add a sender spam rule (address or domain) — future-only — and dismiss this conversation now.
    private func excludeSender(_ convo: EmailConversation, domain: Bool) {
        let opts = EmailExcludeMatching.suggestions(forAddress: convo.fromAddress)
        if let rule = domain ? opts.last : opts.first { EmailExcludeStore.addSender(rule) }
        convo.triageDismiss()
    }

    // Reconcile the other party once for the whole conversation: link → add the address to that Person; create → new.
    private func resolvePerson(_ convo: EmailConversation, _ result: AttendeeReconcileResult) {
        let address = convo.fromAddress
        let person: Person
        switch result {
        case .link(let p):
            if !address.isEmpty { p.emails = Person.appendingEmail(address, to: p.emails) }
            p.updatedAt = Date()
            person = p
        case .create(let name, let inst):
            let p = Person(name: name)
            if !address.isEmpty { p.emails = [address] }
            p.institution = inst
            modelContext.insert(p)
            person = p
        }
        convo.person = person
        for m in convo.messages { m.person = person }
    }

    private func makeProject(_ name: String) -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let project = Project(name: trimmed)
        modelContext.insert(project)
        return project
    }
}

// One triage row for a whole email conversation: quick accept/dismiss/unclassify, open-in-Mail, person
// chip (reconcile once), project chip + inline picker (files the conversation), tap-to-apply project
// suggestions, importance (once), 5/15-min time-logging (against the conversation), and make-todo.
private struct EmailTriageConversationRow: View {
    let conversation: EmailConversation
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

    @Environment(\.modelContext) private var modelContext
    @State private var mailService = MailScriptService()
    @State private var openError: String?
    @State private var editingProject = false
    @State private var confirmingDeleteTasks = false

    private var countText: String {
        var parts: [String] = []
        if conversation.sentCount > 0 { parts.append("\(conversation.sentCount) sent") }
        if conversation.receivedCount > 0 { parts.append("\(conversation.receivedCount) recv") }
        return parts.joined(separator: " · ")
    }
    private var loggedHours: Double { conversation.loggedHours }

    var body: some View {
        // Reads top-to-bottom the way you parse it: subject → summary → the chips/actions you choose from.
        VStack(alignment: .leading, spacing: 2) {
            subjectLine
            summaryLine
            actionRow
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let latest = conversation.latest {
                EmailExperimentInChatButton(email: latest)
                Button("Exclude sender (\(latest.fromAddress))") { onExcludeAddress() }
            }
            Button("Exclude domain") { onExcludeDomain() }
        }
        .alert("Couldn't open email", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(openError ?? "") }
        .alert("Delete \(conversation.taskCount == 1 ? "to-do" : "to-dos")?", isPresented: $confirmingDeleteTasks) {
            Button("Delete", role: .destructive) { onDeleteTasks() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This deletes the to-do\(conversation.taskCount == 1 ? "" : "s") made from this conversation. The emails are kept.") }
    }

    // Line 1: subject · N sent · M recv · open-all-in-Mail envelope, with the send time trailing right.
    private var subjectLine: some View {
        HStack(spacing: 6) {
            Text(conversation.displaySubject)
                .font(.headline)
                .lineLimit(1)
            Text(countText).font(.caption2.weight(.medium)).foregroundStyle(.secondary).fixedSize()
            Button { openInMail() } label: {
                Image(systemName: "envelope").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Open every message in this conversation in Mail")
            Spacer(minLength: 8)
            Text(conversation.date.formatted(date: .omitted, time: .shortened))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // Line 2: the conversation summary (or a "summarising…" hint until ready) — the subject is on line 1.
    @ViewBuilder private var summaryLine: some View {
        if let summary = conversation.latestMessageSummary, !summary.isEmpty {
            Text(summary).font(.callout).lineLimit(2)
        } else if conversation.isSummarizing {
            Text("summarising…").font(.caption2).italic().foregroundStyle(.tertiary)
        }
    }

    // Line 3: the chips + actions, read after the subject/summary. Info/logging on the left, the triage
    // classification (the last thing you do) pushed to the far right.
    private var actionRow: some View {
        HStack(spacing: 6) {
            personChip
            projectChip
            todoChip
            EmailImportancePicker(importance: conversation.importance) { imp in
                conversation.importance = imp
            }
            timeChips
            triageActions
            Spacer(minLength: 8)
        }
    }

    // MARK: - Conversation-level triage state

    private var state: EmailTriageState { conversation.triageState }

    // Move-to-state actions + "make todo".
    @ViewBuilder private var triageActions: some View {
        HStack(spacing: 8) {
            if state != .accepted {
                iconButton("checkmark.circle.fill", AppTheme.completed, "Accept conversation") {
                    conversation.accept()
                }
            }
            if state != .dismissed {
                iconButton("xmark.circle.fill", AppTheme.mutedText, "Dismiss conversation") {
                    conversation.triageDismiss()
                }
            }
            if state != .unclassified {
                iconButton("tray.full", AppTheme.accent, "Move conversation back to triage") {
                    conversation.unclassify()
                }
            }
            iconButton(conversation.taskCount == 0 ? "checklist" : "checklist.checked", AppTheme.action,
                       conversation.taskCount == 0 ? "Make a todo from this conversation" : "Make another todo (\(conversation.taskCount) linked)",
                       onMakeTodo)
        }
    }

    // MARK: - Time-logging (logged against the conversation, which owns its time)

    private func logTime(_ minutes: Int) {
        let nextOrder = (conversation.timeEntries.map(\.sortOrder).max() ?? -1) + 1
        let entry = TaskTimeEntry(date: conversation.date,
                                  duration: Duration(value: Double(minutes) / 60.0, unit: .h),
                                  comment: nil, sortOrder: nextOrder)
        entry.conversation = conversation
        modelContext.insert(entry)
    }

    @ViewBuilder private var timeChips: some View {
        HStack(spacing: 4) {
            if loggedHours > 0 {
                Chip(label: TimeFormat.short(hours: loggedHours), color: AppTheme.duration)
            }
            ForEach([5, 15], id: \.self) { minutes in
                Button { logTime(minutes) } label: {
                    Text("\(minutes)m")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(AppTheme.action.opacity(0.14), in: Capsule())
                        .foregroundStyle(AppTheme.action)
                }
                .buttonStyle(.plain)
                .help("Log \(minutes)m on this conversation")
            }
        }
    }

    // MARK: - To-do chip

    @ViewBuilder private var todoChip: some View {
        if conversation.taskCount > 0 {
            let n = conversation.taskCount
            EmailTodoChip(count: n, hasOpen: conversation.hasOpenTasks, onOpen: onOpenTask)
                .contextMenu {
                    Button("Open to-do") { onOpenTask() }
                    Button(n == 1 ? "Delete to-do" : "Delete to-dos (\(n))", role: .destructive) {
                        confirmingDeleteTasks = true
                    }
                }
        }
    }

    private func iconButton(_ system: String, _ color: Color, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 15)).foregroundStyle(color)
        }
        .buttonStyle(.plain).help(help)
    }

    // Open every message in the conversation in Mail (surface the first failure).
    private func openInMail() {
        for message in conversation.messages {
            mailService.openMessage(message) { result in
                if case .failure(let error) = result, openError == nil { openError = error.userMessage }
            }
        }
    }

    @ViewBuilder private var personChip: some View {
        Button(action: onReconcile) {
            if let person = conversation.person {
                Chip(label: person.name, color: AppTheme.person)
            } else {
                let label = conversation.fromName?.isEmpty == false ? conversation.fromName!
                    : (conversation.fromAddress.isEmpty ? "Unrecognized" : conversation.fromAddress)
                Chip(label: label, color: AppTheme.warning)
            }
        }
        .buttonStyle(.plain)
        .help(conversation.person == nil ? "Unrecognized — click to link/create a person (whole conversation)" : "Linked person — click to change")
    }

    // Files the conversation's project. Assigned → the project (tap to edit). Not assigned but recommended →
    // "+ <Project>" (tap applies). Otherwise "No Project" (tap to choose).
    @ViewBuilder private var projectChip: some View {
        Button { projectTap() } label: {
            if let project = conversation.projects.first {
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
            // Invisible anchor hosting the picker popover; selecting sets the conversation's project set.
            FuzzyPickerField(
                allItems: allProjects,
                selected: Binding(get: { conversation.projects },
                                  set: { conversation.projects = $0 }),
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
        if !conversation.projects.isEmpty { return "Project — click to change (whole conversation)" }
        if suggestions.first != nil { return "Suggested project — click to apply (click again to change)" }
        return "No project — click to choose (whole conversation)"
    }

    private func projectTap() {
        if conversation.projects.isEmpty, let rec = suggestions.first {
            onApplySuggestion(rec)
        } else {
            editingProject = true
        }
    }
}
