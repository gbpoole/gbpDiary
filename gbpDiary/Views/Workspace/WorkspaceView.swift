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
        .sheet(isPresented: $showingNewContent) { ContentNoteEditorSheet(note: nil) }
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
