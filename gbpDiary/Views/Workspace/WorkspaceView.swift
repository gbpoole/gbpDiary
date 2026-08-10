import SwiftUI
import SwiftData

// Obsidian-style shell: a browse sidebar on the left and a tabbed workspace on the right.
// Replaces the old segmented-picker ContentView and the minutes inspector.
struct WorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace
    @Query private var allAttachments: [Attachment]
    @Query private var allNotes: [Note]
    @State private var showingNewContent = false
    #if os(macOS)
    // ⌘W closes the active tab (not the window). See CloseTabKeyMonitor.
    @State private var closeTabMonitor = CloseTabKeyMonitor()
    @State private var hostWindow: NSWindow?
    #endif

    // Image attachments referenced by no note and not attached to a document.
    private var unusedImageCount: Int {
        let referenced = AttachmentUsageScanner.referencedIDs(inContents: allNotes.map(\.content))
        return allAttachments.filter { $0.kind == .image && $0.document == nil && !referenced.contains($0.id) }.count
    }

    var body: some View {
        @Bindable var workspace = workspace
        NavigationSplitView {
            List(selection: Binding(
                get: { workspace.active.current.category },
                set: { if let cat = $0 { workspace.navigate(to: cat.tab) } }
            )) {
                Section("Browse") {
                    ForEach(WorkspaceCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: cat.systemImage)
                            .badge(cat == .images ? unusedImageCount : 0)
                            .tag(cat)
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
        .sheet(isPresented: $showingNewContent) { ContentNoteEditorSheet(note: nil) }
        .onAppear { migratePersonEmails() }
        #if os(macOS)
        .background(WindowAccessor { hostWindow = $0 })
        .onAppear {
            closeTabMonitor.action = { workspace.closeActiveTab() }
            closeTabMonitor.targetWindow = hostWindow
            closeTabMonitor.start()
        }
        .onDisappear { closeTabMonitor.stop() }
        .onChange(of: hostWindow) { _, window in closeTabMonitor.targetWindow = window }
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

    @ViewBuilder
    private var activeContent: some View {
        switch workspace.active.current {
        case .diary:        DiaryView()
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
        }
    }

    private var missing: some View {
        ContentUnavailableView("Not available", systemImage: "questionmark.folder",
                               description: Text("This item may have been deleted."))
    }

    private func model<T: PersistentModel>(_ id: PersistentIdentifier, as _: T.Type) -> T? {
        modelContext.model(for: id) as? T
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
