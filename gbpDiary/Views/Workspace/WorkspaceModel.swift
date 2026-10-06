import Foundation
import SwiftData

// A single open tab in the workspace. **Tabs hold entities only** — the browse categories are fixed
// panes selected in the sidebar, not tabs (see `WorkspaceModel.selectedCategory`). Each case carries the
// entity's stable `PersistentIdentifier`, so the same entity re-opens/activates one tab.
enum WorkspaceTab: Hashable, Identifiable {
    case project(PersistentIdentifier)
    case person(PersistentIdentifier)
    case institution(PersistentIdentifier)
    case minutes(PersistentIdentifier)
    case document(PersistentIdentifier)
    case contentNote(PersistentIdentifier)
    case task(PersistentIdentifier)
    // A curation session, identified by the root project it walks.
    case curation(PersistentIdentifier)
    // An Email Summary Lab session for one email. Its own tab (not a Chat mode) because experiments are
    // transient, per-email and deliberately parallel — the Chat *pane* is a singleton, so it cannot hold
    // one experiment per email the way the old per-tab ChatState did.
    case emailExplorer(PersistentIdentifier)

    var id: Self { self }

    /// The kind of thing this tab shows — drives the chip's icon. It is **not** a sidebar selection:
    /// opening a tab clears the sidebar highlight, because a tab and a category pane are alternatives.
    var category: WorkspaceCategory {
        switch self {
        case .task:                 .tasks
        case .curation, .project:   .projects
        case .person:               .people
        case .institution:          .institutions
        case .minutes:              .meetings
        case .document:             .documents
        case .contentNote:          .content
        case .emailExplorer:        .chat
        }
    }

    /// The model id this tab is keyed on.
    var entityID: PersistentIdentifier {
        switch self {
        case .project(let x), .person(let x), .institution(let x), .minutes(let x),
             .document(let x), .contentNote(let x), .task(let x), .curation(let x),
             .emailExplorer(let x):
            return x
        }
    }
}

// The fixed browse categories shown in the sidebar.
enum WorkspaceCategory: String, CaseIterable, Identifiable {
    case diary        = "Diary"
    case chat         = "Chat"
    case triage       = "Triage"
    case tasks        = "Tasks"
    case timesheet    = "Timesheet"
    case projects     = "Projects"
    case meetings     = "Meetings"
    case people       = "People"
    case institutions = "Institutions"
    case documents    = "Documents"
    case content      = "Content"
    case images       = "Images"
    case tags         = "Tags"

    var id: Self { self }

    // Sidebar/tab display name. Distinct from `rawValue`, which stays stable as a persistence key.
    var title: String {
        switch self {
        case .triage: "Emails"
        default:      rawValue
        }
    }

    // The browse sidebar's grouping: ordered groups, each with a heading, for visual separation.
    static let sidebarGroups: [(title: String, categories: [WorkspaceCategory])] = [
        ("Workspace", [.diary, .tasks, .timesheet, .triage, .chat]),
        ("Records",   [.projects, .meetings, .people, .institutions]),
        ("Library",   [.documents, .content, .images, .tags]),
    ]

    var systemImage: String {
        switch self {
        case .diary:        "calendar"
        case .chat:         "bubble.left.and.bubble.right"
        case .triage:       "tray.and.arrow.down"
        case .tasks:        "checkmark.square"
        case .projects:     "folder"
        case .people:       "person.2"
        case .institutions: "building.2"
        case .meetings:     "person.3.sequence"
        case .documents:    "doc"
        case .content:      "text.book.closed"
        case .images:       "photo.on.rectangle"
        case .tags:         "tag"
        case .timesheet:    "clock"
        }
    }

}

enum ChatMode {
    case database
    case emailExplorerLab
}

struct ChatMessage: Identifiable {
    let id = UUID()
    var role: ChatRole
    var content: String
    var sources: [ChatSourceReference] = []
    var elapsed: TimeInterval? = nil   // wall-clock time to produce an assistant answer
}

enum ChatLabRating: String, CaseIterable, Identifiable {
    case best = "Best"
    case tooVague = "Too vague"
    case missedAction = "Missed action"
    case incorrect = "Incorrect"

    var id: Self { self }
}

struct ChatLabCandidate: Identifiable {
    let id = UUID()
    var summary: String
    var rating: ChatLabRating?
    var isAdopted = false
}

struct ChatLabState {
    var body: String?
    var bodyError: String?
    var isLoadingBody = false
    var instructions = "Emphasise the gist, decisions, requests, deadlines, and actions for the reader. Be specific without adding unsupported facts."
    var includeRelatedContext = true
    var candidates: [ChatLabCandidate] = []
    var isGenerating = false
    var generationError: String?
    var requestToken = 0

    mutating func clearEmailData() {
        requestToken &+= 1
        body = nil
        bodyError = nil
        isLoadingBody = false
        candidates.removeAll()
        isGenerating = false
        generationError = nil
    }
}

/// Per-tab, session-only Chat state. It is intentionally omitted from workspace snapshots.
@Observable final class ChatState {
    var mode: ChatMode = .database
    private(set) var selectedEmailID: PersistentIdentifier?
    private(set) var selectedEmailRevision = 0
    var messages: [ChatMessage] = []
    var draft = ""
    var pendingQuestion = ""
    var isAnswering = false
    var answerError: String?
    var answerRequestToken = 0
    var lab = ChatLabState()

    func selectEmail(_ id: PersistentIdentifier?) {
        guard selectedEmailID != id else { return }
        selectedEmailID = id
        selectedEmailRevision += 1
        lab.clearEmailData()
    }

    func isCurrentEmailRequest(_ id: PersistentIdentifier, revision: Int) -> Bool {
        selectedEmailID == id && selectedEmailRevision == revision
    }

    func isCurrentLabRequest(_ id: PersistentIdentifier, revision: Int, token: Int) -> Bool {
        isCurrentEmailRequest(id, revision: revision) && lab.requestToken == token
    }

    func finishLabGeneration(_ id: PersistentIdentifier, revision: Int, token: Int) {
        guard isCurrentLabRequest(id, revision: revision, token: token) else { return }
        lab.isGenerating = false
    }

    func clearChat() {
        answerRequestToken &+= 1
        messages.removeAll()
        pendingQuestion = ""
        isAnswering = false
        answerError = nil
    }

    func isCurrentAnswerRequest(_ token: Int) -> Bool {
        answerRequestToken == token
    }

    func beginAnswerRequest(_ token: Int) -> String? {
        guard isCurrentAnswerRequest(token), !pendingQuestion.isEmpty, !isAnswering else { return nil }
        let question = pendingQuestion
        pendingQuestion = ""
        isAnswering = true
        return question
    }
}

// One browsing pane: a back/forward history of destinations, like a browser tab. Sidebar
// selection and in-place drilldowns navigate within a single tab; only explicit "open in new
// tab" actions (e.g. meeting minutes) create another tab.
// The Tasks page's two presentations: the normal (Reviewed) table and the inbox Triage list.
// Session-only per tab (not persisted), so dropping a case needs no migration.
enum TaskViewMode: String, CaseIterable {
    case reviewed
    case triage

    var label: String {
        switch self {
        case .reviewed: "Reviewed"
        case .triage:   "Triage"
        }
    }
}

// Per-tab Tasks-page filter state, so filters are remembered when you navigate away and back, and two
// tabs can hold different Tasks filters at once.
@Observable final class TasksFilterState {
    var viewMode: TaskViewMode = .reviewed
    // New Tasks tabs default to showing only incomplete tasks (mirrors ProjectsView's hide-completed).
    var activeFilterIds: Set<String> = ["preset.incomplete"]
    var dateRange: ClosedRange<Date>? = nil
    // Which quick date chip (Today/Week/Month) is lit, if any. Setting one also sets `dateRange`;
    // a custom range from the Filters popover clears this back to nil.
    var datePreset: DateWindow? = nil
    var searchText: String = ""
    var sortOrder: [KeyPathComparator<TaskRow>] = [KeyPathComparator(\.urgency, order: .reverse)]

    // Persistable form of `sortOrder` (the Table's KeyPathComparators aren't Codable).
    static let sortColumns: [SortColumn<TaskRow>] = [
        SortColumn("summary", \.summaryKey), SortColumn("project", \.projectKey),
        SortColumn("status", \.statusRank), SortColumn("priority", \.priorityRank),
        SortColumn("urgency", \.urgency), SortColumn("assignee", \.assigneeKey),
        SortColumn("created", \.createdAt), SortColumn("due", \.dueKey),
        SortColumn("scheduled", \.scheduledKey),
    ]
    var sortDescriptor: (id: String, ascending: Bool) {
        TableSortPersistence.descriptor(for: sortOrder, columns: Self.sortColumns) ?? ("urgency", false)
    }
    func applySort(id: String, ascending: Bool) {
        sortOrder = TableSortPersistence.order(id: id, ascending: ascending, columns: Self.sortColumns, fallbackID: "urgency")
    }
}

// Per-tab filter/search/sort for a shared-style list page (Projects/People/Minutes/Documents/Content/
// Institutions/Tags/Images). Mirrors `TasksFilterState` so these filters survive tab navigation and
// can be persisted. `sortColumnID`/`sortAscending` are the persistable form of the Table's sortOrder
// (see `TableSortPersistence`); each page maps the id to a `KeyPathComparator`.
@Observable final class ListPageFilter {
    var activeFilterIds: Set<String>
    var searchText: String
    var sortColumnID: String
    var sortAscending: Bool

    init(activeFilterIds: Set<String> = [], searchText: String = "",
         sortColumnID: String, sortAscending: Bool) {
        self.activeFilterIds = activeFilterIds
        self.searchText = searchText
        self.sortColumnID = sortColumnID
        self.sortAscending = sortAscending
    }

    /// The default filter for a list-page category (default sort column/order + any seeded filters).
    static func makeDefault(for category: WorkspaceCategory) -> ListPageFilter {
        switch category {
        case .projects:     ListPageFilter(activeFilterIds: ["status.active"], sortColumnID: "name", sortAscending: true)
        case .people:       ListPageFilter(sortColumnID: "name", sortAscending: true)
        case .meetings:     ListPageFilter(sortColumnID: "date", sortAscending: false)
        case .documents:    ListPageFilter(sortColumnID: "created", sortAscending: false)
        case .content:      ListPageFilter(sortColumnID: "updated", sortAscending: false)
        case .institutions: ListPageFilter(sortColumnID: "name", sortAscending: true)
        case .tags:         ListPageFilter(sortColumnID: "tag", sortAscending: true)
        case .images:       ListPageFilter(sortColumnID: "name", sortAscending: true)
        case .diary, .chat, .triage, .tasks, .timesheet:
            ListPageFilter(sortColumnID: "name", sortAscending: true)  // unused (not list pages)
        }
    }
}

@Observable final class WorkspaceTabState: Identifiable {
    let id = UUID()
    /// What this tab shows. A tab is **one entity** — there is no per-tab history or back/forward, because
    /// entity→entity moves open tabs (`focusOrOpen`) and category→entity moves are now a sidebar click.
    let tab: WorkspaceTab
    /// Only an `.emailExplorer` tab uses this: each experiment owns its transient body/candidates/ratings.
    let chatState = ChatState()
    /// How far through a curation walk this tab is. Session-only: the walk itself is recomputed from
    /// live project data, and resuming mid-session after a relaunch would be more surprising than useful.
    var curationIndex: Int = 0

    init(_ tab: WorkspaceTab) {
        self.tab = tab
        if case .emailExplorer(let id) = tab {
            chatState.mode = .emailExplorerLab
            chatState.selectEmail(id)
        }
    }

    func references(_ id: PersistentIdentifier) -> Bool { tab.entityID == id }
}

// The workspace shell's state: **one** selected browse category (a fixed pane) plus the open **entity**
// tabs. Exactly one of the two is showing — picking a sidebar category clears the active tab, and
// activating a tab clears nothing but hides the pane behind it. `activeId == nil` means the pane is up.
//
// Because a category is now a singleton pane rather than a tab, the state that used to be per tab
// (`DiaryState`, `TasksFilterState`, the Database-mode `ChatState`, the list-page filters and the board
// panel's visibility) is held **once, here**. The cost, accepted deliberately: no two Diary pages on
// different dates, and one Database Chat — the Email Summary Lab keeps its parallelism as `.emailExplorer`
// tabs instead.
@Observable final class WorkspaceModel {
    /// The sidebar selection — the pane shown whenever no entity tab is active.
    private(set) var selectedCategory: WorkspaceCategory = .diary
    private(set) var tabs: [WorkspaceTabState]
    /// The active entity tab, or nil while the selected category's pane is showing.
    private(set) var activeId: UUID?

    // MARK: - Single-instance page state (was per tab)

    let diaryState = DiaryState()
    let tasksFilter = TasksFilterState()
    /// The Chat pane's Database-mode state. Email-Explorer state lives on its own tab.
    let chatState = ChatState()
    /// Whether the Tasks page's planning-board panel is open, and whether it fills the width.
    var boardPanelShown: Bool = false
    var boardFullWidth: Bool = false

    // @ObservationIgnored because `pageFilter(for:)` is called from list-page bodies, so the lazy insert
    // is a write during a view update. Nothing observes the cache itself: views observe the returned
    // ListPageFilter, which is @Observable, so identity stays stable and filter edits still publish.
    @ObservationIgnored private var pageFilters: [WorkspaceCategory: ListPageFilter] = [:]
    func pageFilter(for category: WorkspaceCategory) -> ListPageFilter {
        if let existing = pageFilters[category] { return existing }
        let created = ListPageFilter.makeDefault(for: category)
        pageFilters[category] = created
        return created
    }
    /// The page-filter objects actually created so far (for session save).
    var touchedPageFilters: [WorkspaceCategory: ListPageFilter] { pageFilters }
    /// MRU back-stack of *previously* active tab ids (most-recent first). Powers `returnToPreviousTab()`.
    /// Session-only (not persisted); reset on `restore`.
    private(set) var recentTabs: [UUID] = []
    /// A minutes tab that should open straight into minutes-edit mode (e.g. a just-created meeting).
    var autoEditMinutesId: PersistentIdentifier?
    /// A content-note tab that should open straight into edit mode (e.g. a just-created note).
    var autoEditContentId: PersistentIdentifier?

    init() {
        tabs = []
        activeId = nil
    }

    /// The active entity tab, or nil when the category pane is showing.
    var activeTab: WorkspaceTabState? {
        guard let activeId else { return nil }
        return tabs.first { $0.id == activeId }
    }

    /// Show a browse category's pane. Clears the active tab — a pane and a tab are alternatives, so there
    /// is only ever one "what am I looking at".
    func select(_ category: WorkspaceCategory) {
        selectedCategory = category
        setActive(nil)
    }

    /// Open an entity in a brand-new tab and focus it (e.g. meeting minutes).
    func openInNewTab(_ tab: WorkspaceTab) {
        let state = WorkspaceTabState(tab)
        tabs.append(state)
        setActive(state.id)
    }

    /// The single choke point for changing the active tab. When `record` is true it pushes the tab we're
    /// leaving onto the MRU back-stack (deduped, capped) — unless it no longer exists (e.g. it was just
    /// closed). `returnToPreviousTab()` passes `record: false` so a back jump stays progressive.
    private func setActive(_ id: UUID?, record: Bool = true) {
        let old = activeId
        guard old != id else { return }
        if record, let old, tabs.contains(where: { $0.id == old }) {
            recentTabs.removeAll { $0 == old || $0 == id }
            recentTabs.insert(old, at: 0)
            recentTabs = Array(recentTabs.prefix(max(1, tabs.count)))
        } else if let id {
            recentTabs.removeAll { $0 == id }
        }
        activeId = id
    }

    /// Return to the most-recently-active previous tab; pressing repeatedly walks progressively back.
    func returnToPreviousTab() {
        guard let target = recentTabs.first(where: { tid in tabs.contains { $0.id == tid } }) else { return }
        recentTabs.removeAll { $0 == target }
        setActive(target, record: false)   // consume, don't re-push the tab we're leaving → progressive
    }

    /// Reorder the tab strip: move the tab with `id` so it lands at `toIndex` (a chip index, or
    /// `tabs.count` to append). Used by drag-to-reorder; the active tab is unchanged. See `TabReorder`.
    func moveTab(id: UUID, toIndex: Int) {
        let ids = tabs.map(\.id)
        let newOrder = TabReorder.move(ids, id: id, toIndex: toIndex)
        guard newOrder != ids else { return }
        tabs = newOrder.compactMap { tid in tabs.first { $0.id == tid } }
    }

    /// Open an Email Summary Lab tab for this email. **Always a fresh tab** (never reuses another), so
    /// experiments on different emails stay side by side; `WorkspaceTabState.init` configures its mode.
    func openEmailExplorerInNewTab(for email: EmailMessage) {
        openInNewTab(.emailExplorer(email.persistentModelID))
    }

    func activate(_ id: UUID) { setActive(id) }

    // MARK: - Safari-like tab shortcuts

    /// Index of the active tab in `tabs` (0 if somehow not found / pane showing).
    var activeIndex: Int { tabs.firstIndex { $0.id == activeId } ?? 0 }

    /// ⌘W — close the active tab. No-op while the category pane is showing: a pane cannot be closed.
    func closeActiveTab() { if let activeId { closeTab(activeId) } }

    /// ⌘⇧] — focus the next tab, wrapping around to the first.
    func selectNextTab() {
        guard tabs.count > 1 else { return }
        setActive(tabs[(activeIndex + 1) % tabs.count].id)
    }

    /// ⌘⇧[ — focus the previous tab, wrapping around to the last.
    func selectPreviousTab() {
        guard tabs.count > 1 else { return }
        setActive(tabs[(activeIndex - 1 + tabs.count) % tabs.count].id)
    }

    /// ⌘1…⌘8 — focus the tab at a 0-based index; no-op when out of range.
    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        setActive(tabs[index].id)
    }

    /// ⌘9 — focus the last tab (Safari convention).
    func selectLastTab() {
        if let last = tabs.last { setActive(last.id) }
    }

    /// Show the category pane again, leaving every tab open.
    func showSelectedPane() { setActive(nil) }

    /// How far through its walk the active curation tab is. Lives on the tab (each session is its own
    /// tab) but is read and written from `CurationView`, which only knows the model.
    var curationIndex: Int {
        get { activeTab?.curationIndex ?? 0 }
        set { activeTab?.curationIndex = newValue }
    }

    // MARK: - Session persistence

    /// Save the current session (tabs, active tab, diary state, all list-page filters) to UserDefaults.
    func save(using ctx: ModelContext) {
        WorkspaceSessionStore.snapshot = snapshot(using: ctx)
    }

    /// Restore the last saved session from the store (convenience over `restore(_:using:)`).
    func restore(using ctx: ModelContext) {
        restore(WorkspaceSessionStore.snapshot, using: ctx)
    }

    /// Restore a session snapshot: the selected category, the page state, and the entity tabs (resolved by
    /// UUID, dropping any whose entity is gone). A legacy payload is folded first by `migrated()`.
    /// No-op on a nil snapshot.
    func restore(_ snapshot: WorkspaceSnapshot?, using ctx: ModelContext) {
        guard let raw = snapshot else { return }
        let snap = raw.migrated()

        if let category = snap.selectedCategory.flatMap(WorkspaceCategory.init(rawValue:)) {
            selectedCategory = category
        }
        if let d = snap.diary {
            diaryState.currentDate = d.date
            diaryState.mode = DiaryMode(rawValue: d.mode) ?? .day
            diaryState.tracksToday = d.tracksToday
        }
        if let t = snap.tasksFilter { apply(t, to: tasksFilter) }
        for (rawCategory, fs) in snap.pageFilters ?? [:] {
            guard let category = WorkspaceCategory(rawValue: rawCategory) else { continue }
            let pf = pageFilter(for: category)
            pf.activeFilterIds = Set(fs.activeFilterIds)
            pf.searchText = fs.searchText
            pf.sortColumnID = fs.sortColumnID
            pf.sortAscending = fs.sortAscending
        }
        // Absent in sessions written before the board became a panel — treat as closed.
        boardPanelShown = snap.boardPanelShown ?? false
        boardFullWidth = snap.boardFullWidth ?? false

        var restored: [WorkspaceTabState] = []
        var activeIndexAfterDrops: Int?
        for (offset, e) in (snap.entityTabs ?? []).enumerated() {
            guard let tab = workspaceTab(kind: e.kind, id: e.id, using: ctx) else { continue }
            if offset == snap.activeTabIndex { activeIndexAfterDrops = restored.count }
            restored.append(WorkspaceTabState(tab))
        }
        tabs = restored
        recentTabs = []   // fresh session — the MRU back-stack isn't persisted
        // Falling back to the pane is right when the tab that was active has gone: there is always a pane.
        activeId = activeIndexAfterDrops.flatMap { restored.indices.contains($0) ? restored[$0].id : nil }
    }

    func snapshot(using ctx: ModelContext) -> WorkspaceSnapshot {
        var entityTabs: [EntityTabSnapshot] = []
        var activeTabIndex: Int?
        for tab in tabs {
            // An entity deleted out from under an open tab simply isn't saved.
            guard let uuid = entityUUID(for: tab.tab, using: ctx) else { continue }
            if tab.id == activeId { activeTabIndex = entityTabs.count }
            entityTabs.append(EntityTabSnapshot(kind: WorkspaceTabCoding.entityKind(for: tab.tab), id: uuid))
        }
        let d = tasksFilter.sortDescriptor
        let tasks = TasksFilterSnapshot(
            activeFilterIds: Array(tasksFilter.activeFilterIds),
            searchText: tasksFilter.searchText,
            sortColumnID: d.id, sortAscending: d.ascending,
            dateRangeStart: tasksFilter.dateRange?.lowerBound,
            dateRangeEnd: tasksFilter.dateRange?.upperBound,
            datePreset: tasksFilter.datePreset?.rawValue)
        var filters: [String: ListFilterSnapshot] = [:]
        for (category, pf) in touchedPageFilters {
            filters[category.rawValue] = ListFilterSnapshot(
                activeFilterIds: Array(pf.activeFilterIds), searchText: pf.searchText,
                sortColumnID: pf.sortColumnID, sortAscending: pf.sortAscending)
        }
        return WorkspaceSnapshot(
            selectedCategory: selectedCategory.rawValue,
            entityTabs: entityTabs,
            activeTabIndex: activeTabIndex,
            diary: DiarySnapshot(date: diaryState.currentDate,
                                 mode: diaryState.mode.rawValue,
                                 tracksToday: diaryState.tracksToday),
            tasksFilter: tasks,
            pageFilters: filters,
            boardPanelShown: boardPanelShown,
            boardFullWidth: boardFullWidth)
    }

    private func apply(_ snap: TasksFilterSnapshot, to state: TasksFilterState) {
        state.activeFilterIds = Set(snap.activeFilterIds)
        state.searchText = snap.searchText
        state.applySort(id: snap.sortColumnID, ascending: snap.sortAscending)
        if let start = snap.dateRangeStart, let end = snap.dateRangeEnd, start <= end {
            state.dateRange = start...end
        } else {
            state.dateRange = nil
        }
        state.datePreset = snap.datePreset.flatMap(DateWindow.init(rawValue:))
    }

    private func entityUUID(for tab: WorkspaceTab, using ctx: ModelContext) -> UUID? {
        switch tab {
        case .project(let pid):       (ctx.model(for: pid) as? Project)?.id
        case .person(let pid):        (ctx.model(for: pid) as? Person)?.id
        case .institution(let pid):   (ctx.model(for: pid) as? Institution)?.id
        case .minutes(let pid):       (ctx.model(for: pid) as? Minutes)?.id
        case .document(let pid):      (ctx.model(for: pid) as? Document)?.id
        case .contentNote(let pid):   (ctx.model(for: pid) as? Note)?.id
        case .task(let pid):          (ctx.model(for: pid) as? Task)?.id
        case .curation(let pid):      (ctx.model(for: pid) as? Project)?.id
        case .emailExplorer(let pid): (ctx.model(for: pid) as? EmailMessage)?.id
        }
    }

    private func workspaceTab(kind: String, id: UUID, using ctx: ModelContext) -> WorkspaceTab? {
        switch kind {
        case "project":
            return first(FetchDescriptor<Project>(predicate: #Predicate { $0.id == id }), ctx).map { .project($0.persistentModelID) }
        case "person":
            return first(FetchDescriptor<Person>(predicate: #Predicate { $0.id == id }), ctx).map { .person($0.persistentModelID) }
        case "institution":
            return first(FetchDescriptor<Institution>(predicate: #Predicate { $0.id == id }), ctx).map { .institution($0.persistentModelID) }
        case "minutes":
            return first(FetchDescriptor<Minutes>(predicate: #Predicate { $0.id == id }), ctx).map { .minutes($0.persistentModelID) }
        case "document":
            return first(FetchDescriptor<Document>(predicate: #Predicate { $0.id == id }), ctx).map { .document($0.persistentModelID) }
        case "contentNote":
            return first(FetchDescriptor<Note>(predicate: #Predicate { $0.id == id }), ctx).map { .contentNote($0.persistentModelID) }
        case "task":
            return first(FetchDescriptor<Task>(predicate: #Predicate { $0.id == id }), ctx).map { .task($0.persistentModelID) }
        case "curation":
            return first(FetchDescriptor<Project>(predicate: #Predicate { $0.id == id }), ctx).map { .curation($0.persistentModelID) }
        case "emailExplorer":
            // Deliberately NOT restored: a lab session holds only transient, unsaved experiment state, so
            // reopening the tab would present an empty shell. Dropping it is the honest outcome.
            return nil
        default:
            return nil
        }
    }

    private func first<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, _ ctx: ModelContext) -> T? {
        var d = descriptor
        d.fetchLimit = 1
        return (try? ctx.fetch(d))?.first
    }

    /// Open a meeting in a new tab that jumps straight into editing its minutes.
    func openMinutesForEditing(_ id: PersistentIdentifier) {
        autoEditMinutesId = id
        openInNewTab(.minutes(id))
    }

    /// Open a content note in a new tab that jumps straight into editing (e.g. a just-created note).
    func openContentForEditing(_ id: PersistentIdentifier) {
        autoEditContentId = id
        openInNewTab(.contentNote(id))
    }

    /// Activate an existing tab already showing this entity, else open it in a new tab.
    func focusOrOpen(_ tab: WorkspaceTab) {
        if let existing = tabs.first(where: { $0.tab == tab }) {
            setActive(existing.id)
        } else {
            openInNewTab(tab)
        }
    }

    /// Show the Diary pane on the given date and request a scroll to `noteId`. There is one Diary, so
    /// this is a sidebar selection plus a date — no tab hunting.
    func focusDiary(date: Date, scrollTo noteId: UUID? = nil, scrollToEntry entryId: UUID? = nil,
                    scrollToBlock blockId: UUID? = nil) {
        select(.diary)
        diaryState.mode = .day
        diaryState.goTo(date)
        diaryState.scrollTargetNoteId = noteId
        diaryState.scrollTargetEntryId = entryId
        diaryState.scrollTargetBlockId = blockId
    }

    /// Navigate to the diary day where a logged time entry lives, and request a scroll to it.
    func revealTimeEntry(_ entry: TaskTimeEntry) {
        focusDiary(date: entry.date, scrollToEntry: entry.id)
    }

    /// Navigate to the diary day of a focus block and request a scroll to it. No-op if it has no day.
    func revealFocusBlock(_ block: FocusBlock) {
        guard let date = block.dayRecord?.date else { return }
        focusDiary(date: date, scrollToBlock: block.id)
    }

    /// Navigate to the container that holds a note (its day, meeting, or project).
    func reveal(note: Note) {
        if let day = note.dayRecord {
            focusDiary(date: day.date, scrollTo: note.id)
        } else if let minutes = note.minutes {
            focusOrOpen(.minutes(minutes.persistentModelID))
        } else if note.isContentNote {
            focusOrOpen(.contentNote(note.persistentModelID))
        } else if let project = note.project {
            focusOrOpen(.project(project.persistentModelID))
        }
    }

    func closeTab(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        recentTabs.removeAll { $0 == id }   // a closed tab is never a back target
        if tabs.isEmpty {
            // Nothing to fall back *to* any more — the selected category's pane is always there.
            recentTabs = []
            activeId = nil
        } else if activeId == id {
            // Fall back to the tab this one was opened from (the most-recently-active tab), not the
            // positional neighbour; only use the neighbour when there's no recency history.
            if let prev = recentTabs.first(where: { tid in tabs.contains { $0.id == tid } }) {
                recentTabs.removeAll { $0 == prev }
                setActive(prev, record: false)
            } else {
                setActive(tabs[min(idx, tabs.count - 1)].id)
            }
        }
    }

    /// Close any tab showing a now-deleted model id (call before deleting it).
    func closeEntity(_ id: PersistentIdentifier) {
        tabs.filter { $0.references(id) }.forEach { closeTab($0.id) }
    }

    /// Whether any open tab shows this model id (e.g. a meeting shown in a tab).
    func references(_ id: PersistentIdentifier) -> Bool {
        tabs.contains { $0.references(id) }
    }
}
