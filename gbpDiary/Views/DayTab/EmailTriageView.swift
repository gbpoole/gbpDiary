import SwiftUI
import SwiftData

// The central email triage page (sidebar "Emails"). Shows every fetched email (sent + received) across all
// days, **grouped into threads** and segmented by triage bucket (To triage / Accepted / Tasks / Dismissed)
// with global counts, under day headers — so a multi-day backlog is cleared in one place. Triage acts on a
// whole thread at once: accept/dismiss, file the project, set importance, reconcile the person — plus
// quick time-logging (5/10/15 min) and make-todo. Sent mail is unclassified on ingest, so it is triaged
// here like received. Refresh fetches new mail since the last fetch.
struct EmailTriageView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \EmailMessage.date, order: .reverse) private var allEmails: [EmailMessage]
    @Query private var threadSummaries: [EmailThreadSummary]
    @Query(sort: \Project.name) private var allProjects: [Project]
    @Query private var allPeople: [Person]

    @State private var filter: EmailTriageCategory = .toTriage
    @State private var reconciling: EmailMessage?
    @State private var makingTodoFor: EmailMessage?
    @State private var openingTask: Task?
    @State private var service = MailScriptService()
    @State private var isFetching = false
    @State private var status: String?

    // All emails grouped by (day, thread), most-recent day first. Each thread carries its synthesized
    // whole-thread day summary. `allEmails` is date-descending, so day order is descending too.
    private var allDayThreadGroups: [(day: Date, threads: [EmailThread])] {
        let cal = Calendar.current
        var order: [Date] = []
        var byDay: [Date: [EmailMessage]] = [:]
        for email in allEmails {
            let day = cal.startOfDay(for: email.date)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(email)
        }
        return order.map { day in
            let threads = EmailThreadBuilder.threads(from: byDay[day] ?? []).map { thread -> EmailThread in
                var t = thread
                t.synthesizedSummary = EmailThreadBuilder.summaryText(for: thread, in: threadSummaries)
                return t
            }
            return (day, threads)
        }
    }

    private func category(of thread: EmailThread) -> EmailTriageCategory {
        EmailTriageCategory.classifyThread(thread.messages.map { ($0.triageState, $0.hasTasks) })
    }

    // The selected bucket's threads, grouped by day. Days are most-recent first; within a day, threads run
    // in ascending time (earliest → latest).
    private var dayGroups: [(day: Date, threads: [EmailThread])] {
        allDayThreadGroups.compactMap { group in
            let threads = group.threads
                .filter { category(of: $0) == filter }
                .sorted { $0.date < $1.date }
            return threads.isEmpty ? nil : (group.day, threads)
        }
    }

    private func count(_ category: EmailTriageCategory) -> Int {
        allDayThreadGroups.reduce(0) { $0 + $1.threads.filter { self.category(of: $0) == category }.count }
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
                            ForEach(group.threads) { thread in
                                EmailTriageThreadRow(
                                    thread: thread, allProjects: allProjects,
                                    suggestions: suggestions(for: thread.latest),
                                    makeProject: makeProject,
                                    onApplySuggestion: { apply($0, to: thread) },
                                    onReconcile: { reconciling = thread.latest },
                                    onExcludeAddress: { excludeSender(thread, domain: false) },
                                    onExcludeDomain: { excludeSender(thread, domain: true) },
                                    onMakeTodo: { makingTodoFor = thread.latest },
                                    onOpenTask: { openingTask = thread.tasks.first },
                                    onDeleteTasks: { deleteTasks(of: thread) })
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
                onTaskCreated: { task in task.originEmail = email; acceptThread(of: email) },
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

    // MARK: - Thread membership helpers

    // All emails in the same (day + subject) thread as `email` — so a triage action applies to the whole
    // conversation even after a re-render rebuilds the EmailThread value.
    private func threadMessages(of email: EmailMessage) -> [EmailMessage] {
        let cal = Calendar.current
        let key = EmailThreadBuilder.threadKey(for: email)
        return allEmails.filter {
            cal.isDate($0.date, inSameDayAs: email.date) && EmailThreadBuilder.threadKey(for: $0) == key
        }
    }

    private func acceptThread(of email: EmailMessage) {
        for m in threadMessages(of: email) { m.accept() }
    }

    private func deleteTasks(of thread: EmailThread) {
        for task in thread.tasks { modelContext.delete(task) }
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
        let key = EmailThreadBuilder.threadKey(for: email)
        var prior: [UUID] = []
        for other in allEmails where other.id != email.id {
            let sameSender = !email.fromAddress.isEmpty
                && other.fromAddress.caseInsensitiveCompare(email.fromAddress) == .orderedSame
            let sameThread = EmailThreadBuilder.threadKey(for: other) == key
            if sameSender || sameThread { prior.append(contentsOf: other.projects.map(\.id)) }
        }
        let input = EmailProjectSuggestions.Input(assignedIDs: assigned, senderProjectIDs: senderProjects,
                                                  priorProjectIDs: prior, aiSuggestedID: email.suggestedProjectID)
        return EmailProjectSuggestions.rank(input, projects: projects)
    }

    // Apply a suggested project to every message in the thread (dedup).
    private func apply(_ ref: ProjectRef, to thread: EmailThread) {
        guard let project = allProjects.first(where: { $0.id == ref.id }) else { return }
        for m in thread.messages where !m.projects.contains(where: { $0.id == project.id }) {
            m.projects.append(project)
        }
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

    // Add a sender spam rule (address or domain) — future-only — and dismiss this whole thread now.
    private func excludeSender(_ thread: EmailThread, domain: Bool) {
        let opts = EmailExcludeMatching.suggestions(forAddress: thread.latest.fromAddress)
        if let rule = domain ? opts.last : opts.first { EmailExcludeStore.addSender(rule) }
        for m in thread.messages { m.triageDismiss() }
    }

    // Reconcile the other party once for the whole thread: link → add the address to that Person; create → new.
    private func resolvePerson(_ email: EmailMessage, _ result: AttendeeReconcileResult) {
        let messages = threadMessages(of: email)
        switch result {
        case .link(let p):
            if !email.fromAddress.isEmpty { p.emails = Person.appendingEmail(email.fromAddress, to: p.emails) }
            p.updatedAt = Date()
            for m in messages { m.person = p }
        case .create(let name, let inst):
            let p = Person(name: name)
            if !email.fromAddress.isEmpty { p.emails = [email.fromAddress] }
            p.institution = inst
            modelContext.insert(p)
            for m in messages { m.person = p }
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

// One triage row for a whole email thread: quick accept/dismiss/unclassify (applied to every message),
// open-in-Mail, person chip (reconcile once), project chip + inline picker (files the whole thread),
// tap-to-apply project suggestions, importance (once), 5/10/15-min time-logging, and make-todo.
private struct EmailTriageThreadRow: View {
    let thread: EmailThread
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
        if thread.sentCount > 0 { parts.append("\(thread.sentCount) sent") }
        if thread.receivedCount > 0 { parts.append("\(thread.receivedCount) recv") }
        return parts.joined(separator: " · ")
    }
    private var loggedHours: Double {
        thread.messages.flatMap(\.timeEntries).reduce(0.0) { $0 + $1.duration.hoursNormalized }
    }

    var body: some View {
        // Reads top-to-bottom the way you parse it: subject → summary → the chips/actions you choose from.
        VStack(alignment: .leading, spacing: 2) {
            subjectLine
            summaryLine
            actionRow
        }
        .padding(.vertical, 2)
        .contextMenu {
            EmailExperimentInChatButton(email: thread.latest)
            Button("Exclude sender (\(thread.latest.fromAddress))") { onExcludeAddress() }
            Button("Exclude domain") { onExcludeDomain() }
        }
        .alert("Couldn't open email", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(openError ?? "") }
        .alert("Delete \(thread.taskCount == 1 ? "to-do" : "to-dos")?", isPresented: $confirmingDeleteTasks) {
            Button("Delete", role: .destructive) { onDeleteTasks() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This deletes the to-do\(thread.taskCount == 1 ? "" : "s") made from this thread. The emails are kept.") }
    }

    // Line 1: subject · N sent · M recv · open-all-in-Mail envelope, with the send time trailing right.
    private var subjectLine: some View {
        HStack(spacing: 6) {
            Text(thread.displaySubject)
                .font(.headline)
                .lineLimit(1)
            Text(countText).font(.caption2.weight(.medium)).foregroundStyle(.secondary).fixedSize()
            Button { openInMail() } label: {
                Image(systemName: "envelope").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Open every message in this thread in Mail")
            Spacer(minLength: 8)
            Text(thread.date.formatted(date: .omitted, time: .shortened))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // Line 2: the whole-thread summary (or a "summarising…" hint until ready) — the subject is on line 1.
    @ViewBuilder private var summaryLine: some View {
        if let summary = thread.summary, !summary.isEmpty {
            Text(summary).font(.callout).lineLimit(2)
        } else if thread.isSummarizing {
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
            EmailImportancePicker(importance: thread.importance) { imp in
                for m in thread.messages { m.importance = imp }
            }
            timeChips
            triageActions
            Spacer(minLength: 8)
        }
    }

    // MARK: - Thread-level triage state

    private var canAccept: Bool { thread.messages.contains { $0.triageState != .accepted } }
    private var canDismiss: Bool { thread.messages.contains { $0.triageState != .dismissed } }
    private var canUnclassify: Bool { thread.messages.contains { $0.triageState != .unclassified } }

    // Move-to-state actions (applied to every message) + "make todo".
    @ViewBuilder private var triageActions: some View {
        HStack(spacing: 8) {
            if canAccept {
                iconButton("checkmark.circle.fill", AppTheme.completed, "Accept thread") {
                    for m in thread.messages { m.accept() }
                }
            }
            if canDismiss {
                iconButton("xmark.circle.fill", AppTheme.mutedText, "Dismiss thread") {
                    for m in thread.messages { m.triageDismiss() }
                }
            }
            if canUnclassify {
                iconButton("tray.full", AppTheme.accent, "Move thread back to triage") {
                    for m in thread.messages { m.unclassify() }
                }
            }
            iconButton(thread.taskCount == 0 ? "checklist" : "checklist.checked", AppTheme.action,
                       thread.taskCount == 0 ? "Make a todo from this thread" : "Make another todo (\(thread.taskCount) linked)",
                       onMakeTodo)
        }
    }

    // MARK: - Time-logging (logs against the latest sent message, else the latest message)

    private var timeTarget: EmailMessage { thread.messages.first { $0.direction == .sent } ?? thread.latest }

    private func logTime(_ minutes: Int) {
        let target = timeTarget
        let nextOrder = (target.timeEntries.map(\.sortOrder).max() ?? -1) + 1
        let entry = TaskTimeEntry(date: target.date,
                                  duration: Duration(value: Double(minutes) / 60.0, unit: .h),
                                  comment: nil, sortOrder: nextOrder)
        entry.email = target
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
                .help("Log \(minutes)m on this thread")
            }
        }
    }

    // MARK: - To-do chip

    @ViewBuilder private var todoChip: some View {
        if thread.taskCount > 0 {
            let n = thread.taskCount
            EmailTodoChip(count: n, hasOpen: thread.hasOpenTasks, onOpen: onOpenTask)
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

    // Open every message in the thread in Mail (surface the first failure).
    private func openInMail() {
        for message in thread.messages {
            mailService.openMessage(message) { result in
                if case .failure(let error) = result, openError == nil { openError = error.userMessage }
            }
        }
    }

    @ViewBuilder private var personChip: some View {
        Button(action: onReconcile) {
            if let person = thread.person {
                Chip(label: person.name, color: AppTheme.person)
            } else {
                let label = thread.fromName?.isEmpty == false ? thread.fromName!
                    : (thread.fromAddress.isEmpty ? "Unrecognized" : thread.fromAddress)
                Chip(label: label, color: AppTheme.warning)
            }
        }
        .buttonStyle(.plain)
        .help(thread.person == nil ? "Unrecognized — click to link/create a person (whole thread)" : "Linked person — click to change")
    }

    // Files the whole thread's project. Assigned → the project (tap to edit). Not assigned but recommended →
    // "+ <Project>" (tap applies to all messages). Otherwise "No Project" (tap to choose).
    @ViewBuilder private var projectChip: some View {
        Button { projectTap() } label: {
            if let project = thread.projects.first {
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
            // Invisible anchor hosting the picker popover; selecting sets the SAME project set on every message.
            FuzzyPickerField(
                allItems: allProjects,
                selected: Binding(get: { thread.projects },
                                  set: { newProjects in for m in thread.messages { m.projects = newProjects } }),
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
        if !thread.projects.isEmpty { return "Project — click to change (whole thread)" }
        if suggestions.first != nil { return "Suggested project — click to apply to the thread (click again to change)" }
        return "No project — click to choose (whole thread)"
    }

    private func projectTap() {
        if thread.projects.isEmpty, let rec = suggestions.first {
            onApplySuggestion(rec)
        } else {
            editingProject = true
        }
    }
}
