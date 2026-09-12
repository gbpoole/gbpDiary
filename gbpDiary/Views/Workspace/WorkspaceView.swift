import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

// Obsidian-style shell: a browse sidebar on the left and a tabbed workspace on the right.
// Replaces the old segmented-picker ContentView and the minutes inspector.
struct WorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(HotkeySettings.self) private var hotkeys
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allAttachments: [Attachment]
    @Query private var allNotes: [Note]
    @Query private var allEmails: [EmailMessage]
    @Query private var allTasks: [Task]
    @State private var showingNewContent = false
    // Restore the saved session exactly once, when the workspace first appears (has a modelContext).
    @State private var hasRestored = false
    #if os(macOS)
    // ⌘W closes the active tab (not the window). See CloseTabKeyMonitor.
    @State private var closeTabMonitor = CloseTabKeyMonitor()
    @State private var hostWindow: NSWindow?
    #endif

    // Emails awaiting triage across all fetched days (the Emails sidebar backlog badge).
    private var triageBacklogCount: Int {
        allEmails.filter { $0.triageState == .unclassified }.count
    }

    // Open, top-level tasks awaiting Review (the Tasks sidebar inbox badge).
    private var taskInboxCount: Int {
        allTasks.filter { $0.needsTriage && $0.parent == nil && $0.isOpen }.count
    }

    // Image attachments referenced by no note and not attached to a document.
    private var unusedImageCount: Int {
        let referenced = AttachmentUsageScanner.referencedIDs(inContents: allNotes.map(\.content))
        return allAttachments.filter { $0.kind == .image && $0.document == nil && !referenced.contains($0.id) }.count
    }

    private func badgeCount(for cat: WorkspaceCategory) -> Int {
        switch cat {
        case .triage: triageBacklogCount
        case .tasks:  taskInboxCount
        case .images: unusedImageCount
        default:      0
        }
    }

    var body: some View {
        @Bindable var workspace = workspace
        NavigationSplitView {
            List(selection: Binding(
                get: { workspace.active.current.category },
                set: { if let cat = $0 { workspace.navigate(to: cat.tab) } }
            )) {
                ForEach(WorkspaceCategory.sidebarGroups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.categories) { cat in
                            Label(cat.title, systemImage: cat.systemImage)
                                .badge(badgeCount(for: cat))
                                .tag(cat)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
            .background(AppTheme.sidebarBackground)
            .safeAreaInset(edge: .bottom) {
                Button { showingNewContent = true } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accent)
                .padding(8)
                .help("Create a new Content note")
            }
        } detail: {
            VStack(spacing: 0) {
                WorkspaceTabStrip()
                Divider()
                activeContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(workspace.active.current)
            }
            .background(AppTheme.background)
        }
        .environment(workspace.active.diaryState)
        .kanagawaAppBackground()
        .background { TaskRecurrenceDriver() } // spawn recurring tasks + auto-cancel past-until tasks
        .background { EmailFetchDriver() }     // global auto-ingest (last few days, 5-min cadence)
        .background { EmailSummaryDriver() }   // global on-device email summarisation
        .background { EmailThreadSummaryDriver() } // global on-device whole-thread day summaries
        .background { ChatIndexDriver() }      // rebuildable local semantic index + stale-source removal
        .sheet(isPresented: $showingNewContent) { ContentNoteEditorSheet(note: nil) }
        .onAppear {
            if !hasRestored {
                workspace.restore(using: modelContext)
                hasRestored = true
            }
            migratePersonEmails()
            migrateEmailConversationsOnce()
            migrateFocusBlockProjectsOnce()
            migrateFocusBlockDescriptionsOnce()
        }
        // Persist the session when the app deactivates/backgrounds (covers ⌘Q and app switches).
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { workspace.save(using: modelContext) }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            workspace.save(using: modelContext)
        }
        .background(WindowAccessor { hostWindow = $0 })
        .onAppear {
            closeTabMonitor.action = { workspace.closeActiveTab() }
            closeTabMonitor.targetWindow = hostWindow
            closeTabMonitor.hotkey = hotkeys.hotkey(for: .closeTab)
            closeTabMonitor.start()
        }
        .onDisappear { closeTabMonitor.stop() }
        .onChange(of: hostWindow) { _, window in closeTabMonitor.targetWindow = window }
        .onChange(of: hotkeys.hotkey(for: .closeTab)) { _, hk in closeTabMonitor.hotkey = hk }
        #endif
    }

    // One-time migration of the legacy single `Person.email` into the ordered `emails` list.
    // Idempotent: a Person is only touched while it still has a legacy value and an empty list.
    private func migratePersonEmails() {
        let people = (try? modelContext.fetch(FetchDescriptor<Person>())) ?? []
        var changed = false
        for p in people {
            if let migrated = Person.migratedEmails(legacyEmail: p.email, existingEmails: p.emails) {
                p.emails = migrated
                p.email = nil
                changed = true
            }
        }
        if changed { try? modelContext.save() }
    }

    // One-time: build `EmailConversation` entities for all existing emails (reply-graph where headers are
    // present, subject fallback otherwise), folding each email's legacy triage/project/person/importance/
    // time onto its conversation. Guarded by a flag; ongoing ingest keeps conversations current after this.
    private func migrateEmailConversationsOnce() {
        let key = "email.conversationsMigrated.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let emails = (try? modelContext.fetch(FetchDescriptor<EmailMessage>())) ?? []
        if !emails.isEmpty {
            EmailConversationReconciler.reconcile(emails: emails, context: modelContext)
            try? modelContext.save()
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    // One-time: time can only be assigned to tasks, not projects. Fix any focus block still carrying a legacy
    // `project` — a project-only block (no task) is backed by one auto-created, already-completed task per
    // project; a task-backed block just has its stale project cleared (the task owns the project). Idempotent
    // by design: a fixed block no longer carries a project, so `FocusBlockProjectMigration.plan` skips it.
    private func migrateFocusBlockProjectsOnce() {
        let blocks = (try? modelContext.fetch(FetchDescriptor<FocusBlock>())) ?? []
        let plan = FocusBlockProjectMigration.plan(blocks.map {
            FocusBlockProjectMigration.Input(blockID: $0.id, hasTask: $0.task != nil, projectID: $0.project?.id)
        })
        guard !plan.isEmpty else { return }

        let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })

        if !plan.tasksPerProject.isEmpty {
            let me = AppSettingsStore.myPersonID.flatMap { id in
                (try? modelContext.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })))?.first
            }
            for (_, blockIDs) in plan.tasksPerProject {
                let migratedBlocks = blockIDs.compactMap { byID[$0] }
                guard let project = migratedBlocks.first?.project else { continue }
                // A synthetic, already-completed stand-in for historical planned time on this project.
                let task = Task(summary: project.name)
                task.project = project
                task.assignee = me
                task.markReviewed()
                task.markCompleted()
                modelContext.insert(task)
                for block in migratedBlocks {
                    block.task = task
                    block.project = nil
                }
            }
        }

        // Task-backed blocks with a stale legacy project (e.g. Obsidian-imported): the task owns the project.
        for blockID in plan.clearProject { byID[blockID]?.project = nil }

        try? modelContext.save()
    }

    // One-time (flag-guarded): the Obsidian import named each block's task after its PROJECT and put the real
    // description in the block's `comment`. Re-point each described block onto a task named after its
    // description (one task per (project, description) group — repeated days share it), keeping the block so
    // its net-capacity behavior is unchanged. No time entries are created.
    private func migrateFocusBlockDescriptionsOnce() {
        let key = "focusblock.descriptionTasks.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let blocks = (try? modelContext.fetch(FetchDescriptor<FocusBlock>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        let groups = FocusBlockDescriptionMigration.plan(blocks.map {
            FocusBlockDescriptionMigration.Input(blockID: $0.id, description: $0.comment,
                                                 projectID: ($0.task?.project ?? $0.project)?.id)
        })

        if !groups.isEmpty {
            let projectsByID = Dictionary(uniqueKeysWithValues:
                ((try? modelContext.fetch(FetchDescriptor<Project>())) ?? []).map { ($0.id, $0) })
            let me = AppSettingsStore.myPersonID.flatMap { id in
                (try? modelContext.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })))?.first
            }

            var orphanCandidates = Set<Task>()
            for group in groups {
                let task = Task(summary: group.description)
                task.project = group.projectID.flatMap { projectsByID[$0] }
                task.assignee = me
                task.markReviewed()
                task.markCompleted()
                modelContext.insert(task)
                for blockID in group.blockIDs {
                    guard let block = byID[blockID] else { continue }
                    if let old = block.task { orphanCandidates.insert(old) }
                    block.task = task
                    block.comment = nil   // the description now lives in the task summary
                }
            }

            // Delete import-artifact shells left with nothing attached (summary == project name, no blocks /
            // time entries / children). Real or still-used tasks are untouched.
            for old in orphanCandidates
            where old.focusBlocks.isEmpty && old.timeEntries.isEmpty && old.children.isEmpty
                && old.summary == old.project?.name {
                modelContext.delete(old)
            }
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    @ViewBuilder
    private var activeContent: some View {
        switch workspace.active.current {
        case .diary:        DiaryView()
        case .chat:         ChatView(state: workspace.active.chatState)
        case .triage:       EmailTriageView()
        case .tasks:        TasksView()
        case .projects:     ProjectsView()
        case .people:       PeopleView()
        case .institutions: InstitutionsView()
        case .meetings:     MinutesListView()
        case .documents:    DocumentsListView()
        case .content:      ContentListView()
        case .images:       ImageLibraryView()
        case .tags:         TagsView()
        case .timesheet:    TimesheetView()

        case .contentNote(let pid):
            if let n = model(pid, as: Note.self) { ContentNoteDetailView(note: n) } else { missing }
        case .project(let pid):
            if let p = model(pid, as: Project.self) { ProjectDetailView(project: p) } else { missing }
        case .person(let pid):
            if let p = model(pid, as: Person.self) { PersonDetailView(person: p) } else { missing }
        case .institution(let pid):
            if let i = model(pid, as: Institution.self) { InstitutionDetailView(institution: i) } else { missing }
        case .minutes(let pid):
            if let m = model(pid, as: Minutes.self) { MinutesDetailView(minutes: m) } else { missing }
        case .document(let pid):
            if let d = model(pid, as: Document.self) { DocumentDetailView(document: d) } else { missing }
        case .task(let pid):
            if let t = model(pid, as: Task.self) { TaskDetailView(task: t) } else { missing }
        }
    }

    private var missing: some View {
        ContentUnavailableView("Not available", systemImage: "questionmark.folder",
                               description: Text("This item may have been deleted."))
    }

    // Deleted-aware: a model deleted this session resolves via `model(for:)` as a tombstone whose property
    // reads trap — so exclude it here and render `missing` instead of crashing inside the detail view.
    private func model<T: PersistentModel>(_ id: PersistentIdentifier, as _: T.Type) -> T? {
        modelContext.liveModel(id, as: T.self)
    }
}

#if os(macOS)
// Resolves the NSWindow hosting this SwiftUI view (nil until it attaches to the window). Used to
// scope CloseTabKeyMonitor to the workspace window.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view isn't in the window hierarchy yet during make; resolve on the next runloop tick.
        DispatchQueue.main.async { [weak view] in onResolve(view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        onResolve(nsView.window)
    }
}
#endif
