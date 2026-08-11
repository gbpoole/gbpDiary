import Foundation
import SwiftData

// A single open tab in the workspace. Category tabs are singletons; entity tabs carry the
// entity's stable `PersistentIdentifier` so the same entity re-opens/activates one tab.
enum WorkspaceTab: Hashable, Identifiable {
    case diary
    case chat
    case tasks
    case projects
    case people
    case institutions
    case meetings
    case documents
    case images
    case tags
    case timesheet
    case content

    case project(PersistentIdentifier)
    case person(PersistentIdentifier)
    case institution(PersistentIdentifier)
    case minutes(PersistentIdentifier)
    case document(PersistentIdentifier)
    case contentNote(PersistentIdentifier)

    var id: Self { self }

    // The sidebar category this tab belongs to (used to highlight the sidebar selection).
    var category: WorkspaceCategory {
        switch self {
        case .diary:                     .diary
        case .chat:                      .chat
        case .tasks:                     .tasks
        case .projects, .project:        .projects
        case .people, .person:           .people
        case .institutions, .institution: .institutions
        case .meetings, .minutes:        .meetings
        case .documents, .document:      .documents
        case .images:                    .images
        case .tags:                      .tags
        case .timesheet:                 .timesheet
        case .content, .contentNote:     .content
        }
    }
}

// The fixed browse categories shown in the sidebar.
enum WorkspaceCategory: String, CaseIterable, Identifiable {
    case diary        = "Diary"
    case chat         = "Chat"
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

    var systemImage: String {
        switch self {
        case .diary:        "calendar"
        case .chat:         "bubble.left.and.bubble.right"
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

    // The list/tool tab opened when the category is selected in the sidebar.
    var tab: WorkspaceTab {
        switch self {
        case .diary:        .diary
        case .chat:         .chat
        case .tasks:        .tasks
        case .projects:     .projects
        case .people:       .people
        case .institutions: .institutions
        case .meetings:     .meetings
        case .documents:    .documents
        case .content:      .content
        case .images:       .images
        case .tags:         .tags
        case .timesheet:    .timesheet
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
// Per-tab Tasks-page filter state, so filters are remembered when you navigate away and back, and two
// tabs can hold different Tasks filters at once.
@Observable final class TasksFilterState {
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
        case .diary, .chat, .tasks, .timesheet:
            ListPageFilter(sortColumnID: "name", sortAscending: true)  // unused (not list pages)
        }
    }
}

@Observable final class WorkspaceTabState: Identifiable {
    let id = UUID()
    // Per-tab Diary browsing state so two tabs showing the Diary can be on different dates.
    let diaryState = DiaryState()
    // Per-tab Chat state is session-only and starts fresh after workspace restoration.
    let chatState = ChatState()
    // Per-tab Tasks-page filter state (remembered across in-tab navigation).
    let tasksFilter = TasksFilterState()
    // Per-tab filter state for the other shared-style list pages, created lazily with page defaults.
    private var pageFilters: [WorkspaceCategory: ListPageFilter] = [:]
    func pageFilter(for category: WorkspaceCategory) -> ListPageFilter {
        if let existing = pageFilters[category] { return existing }
        let created = ListPageFilter.makeDefault(for: category)
        pageFilters[category] = created
        return created
    }
    private(set) var history: [WorkspaceTab]
    private(set) var index: Int

    var current: WorkspaceTab { history[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < history.count - 1 }

    init(_ tab: WorkspaceTab) {
        history = [tab]
        index = 0
    }

    /// Rebuild a tab from a persisted history (used at session restore). Falls back to a Diary tab
    /// when the history is empty; clamps `index` into range.
    init(history: [WorkspaceTab], index: Int) {
        let safe = history.isEmpty ? [.diary] : history
        self.history = safe
        self.index = min(max(0, index), safe.count - 1)
    }

    /// The page-filter objects that have actually been created on this tab (for session save).
    var touchedPageFilters: [WorkspaceCategory: ListPageFilter] { pageFilters }

    func navigate(to tab: WorkspaceTab) {
        guard current != tab else { return }
        if index < history.count - 1 { history.removeSubrange((index + 1)...) }
        history.append(tab)
        index = history.count - 1
    }

    func goBack() { if canGoBack { index -= 1 } }
    func goForward() { if canGoForward { index += 1 } }

    func references(_ id: PersistentIdentifier) -> Bool {
        history.contains { tab in
            switch tab {
            case .project(let x), .person(let x), .institution(let x),
                 .minutes(let x), .document(let x), .contentNote(let x):
                return x == id
            default:
                return false
            }
        }
    }
}

// Holds the open tabs (each a browsing history) and the active tab. Replaces the old
// MinutesEditorContext — minutes now open as a new tab rather than a side inspector.
@Observable final class WorkspaceModel {
    private(set) var tabs: [WorkspaceTabState]
    var activeId: UUID
    /// A minutes tab that should open straight into minutes-edit mode (e.g. a just-created meeting).
    var autoEditMinutesId: PersistentIdentifier?
    /// A content-note tab that should open straight into edit mode (e.g. a just-created note).
    var autoEditContentId: PersistentIdentifier?

    init() {
        let first = WorkspaceTabState(.diary)
        tabs = [first]
        activeId = first.id
    }

    var active: WorkspaceTabState { tabs.first { $0.id == activeId } ?? tabs[0] }

    /// Navigate the active tab in place (sidebar selection, list drilldowns).
    func navigate(to tab: WorkspaceTab) { active.navigate(to: tab) }

    /// Open a destination in a brand-new tab and focus it (e.g. meeting minutes).
    func openInNewTab(_ tab: WorkspaceTab) {
        let state = WorkspaceTabState(tab)
        tabs.append(state)
        activeId = state.id
    }

    /// Reorder the tab strip: move the tab with `id` so it lands at `toIndex` (a chip index, or
    /// `tabs.count` to append). Used by drag-to-reorder; the active tab is unchanged. See `TabReorder`.
    func moveTab(id: UUID, toIndex: Int) {
        let ids = tabs.map(\.id)
        let newOrder = TabReorder.move(ids, id: id, toIndex: toIndex)
        guard newOrder != ids else { return }
        tabs = newOrder.compactMap { tid in tabs.first { $0.id == tid } }
    }

    /// Always open a fresh Chat tab configured for exploring the selected email.
    func openEmailExplorerInNewTab(for email: EmailMessage) {
        let state = WorkspaceTabState(.chat)
        state.chatState.mode = .emailExplorerLab
        state.chatState.selectEmail(email.persistentModelID)
        tabs.append(state)
        activeId = state.id
    }

    func activate(_ id: UUID) { activeId = id }

    // MARK: - Safari-like tab shortcuts

    /// Index of the active tab in `tabs` (0 if somehow not found).
    var activeIndex: Int { tabs.firstIndex { $0.id == activeId } ?? 0 }

    /// ⌘T — open a fresh Diary tab and focus it.
    func newTab() { openInNewTab(.diary) }

    /// ⌘W — close the active tab (recreates a Diary tab if it was the last one, via `closeTab`).
    func closeActiveTab() { closeTab(activeId) }

    /// ⌘⇧] — focus the next tab, wrapping around to the first.
    func selectNextTab() {
        guard tabs.count > 1 else { return }
        activeId = tabs[(activeIndex + 1) % tabs.count].id
    }

    /// ⌘⇧[ — focus the previous tab, wrapping around to the last.
    func selectPreviousTab() {
        guard tabs.count > 1 else { return }
        activeId = tabs[(activeIndex - 1 + tabs.count) % tabs.count].id
    }

    /// ⌘1…⌘8 — focus the tab at a 0-based index; no-op when out of range.
    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        activeId = tabs[index].id
    }

    /// ⌘9 — focus the last tab (Safari convention).
    func selectLastTab() {
        if let last = tabs.last { activeId = last.id }
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

    /// Restore a session snapshot, resolving entity tabs by UUID and dropping any whose entity was
    /// deleted. No-op (keeps the current tabs) when the snapshot is nil/empty or nothing resolves.
    func restore(_ snapshot: WorkspaceSnapshot?, using ctx: ModelContext) {
        guard let snap = snapshot, !snap.tabs.isEmpty else { return }
        var restored: [WorkspaceTabState] = []
        for tabSnap in snap.tabs {
            let destinations = tabSnap.history.compactMap { workspaceTab(for: $0, using: ctx) }
            guard !destinations.isEmpty else { continue }
            let state = WorkspaceTabState(history: destinations, index: tabSnap.index)
            state.diaryState.currentDate = tabSnap.diary.date
            state.diaryState.mode = DiaryMode(rawValue: tabSnap.diary.mode) ?? .day
            state.diaryState.tracksToday = tabSnap.diary.tracksToday
            apply(tabSnap.tasksFilter, to: state.tasksFilter)
            for (rawCategory, fs) in tabSnap.pageFilters {
                guard let category = WorkspaceCategory(rawValue: rawCategory) else { continue }
                let pf = state.pageFilter(for: category)
                pf.activeFilterIds = Set(fs.activeFilterIds)
                pf.searchText = fs.searchText
                pf.sortColumnID = fs.sortColumnID
                pf.sortAscending = fs.sortAscending
            }
            restored.append(state)
        }
        guard !restored.isEmpty else { return }
        tabs = restored
        activeId = restored[min(max(0, snap.activeIndex), restored.count - 1)].id
    }

    func snapshot(using ctx: ModelContext) -> WorkspaceSnapshot {
        let tabSnaps = tabs.map { tab -> TabSnapshot in
            let history = tab.history.compactMap { destination(for: $0, using: ctx) }
            let index = min(max(0, tab.index), max(0, history.count - 1))
            let d = tab.tasksFilter.sortDescriptor
            let tasks = TasksFilterSnapshot(
                activeFilterIds: Array(tab.tasksFilter.activeFilterIds),
                searchText: tab.tasksFilter.searchText,
                sortColumnID: d.id, sortAscending: d.ascending,
                dateRangeStart: tab.tasksFilter.dateRange?.lowerBound,
                dateRangeEnd: tab.tasksFilter.dateRange?.upperBound,
                datePreset: tab.tasksFilter.datePreset?.rawValue)
            var pageFilters: [String: ListFilterSnapshot] = [:]
            for (category, pf) in tab.touchedPageFilters {
                pageFilters[category.rawValue] = ListFilterSnapshot(
                    activeFilterIds: Array(pf.activeFilterIds), searchText: pf.searchText,
                    sortColumnID: pf.sortColumnID, sortAscending: pf.sortAscending)
            }
            return TabSnapshot(
                history: history, index: index,
                diary: DiarySnapshot(date: tab.diaryState.currentDate,
                                     mode: tab.diaryState.mode.rawValue,
                                     tracksToday: tab.diaryState.tracksToday),
                tasksFilter: tasks, pageFilters: pageFilters)
        }
        // Keep active index valid even if some tabs produced empty histories (rare; entity gone).
        let validTabs = tabSnaps.enumerated().filter { !$0.element.history.isEmpty }
        let snapshotTabs = validTabs.map(\.element)
        let newActive = validTabs.firstIndex { $0.offset == activeIndex } ?? 0
        return WorkspaceSnapshot(tabs: snapshotTabs, activeIndex: newActive)
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

    private func destination(for tab: WorkspaceTab, using ctx: ModelContext) -> TabDestination? {
        if let token = WorkspaceTabCoding.token(forCategoryTab: tab) { return .page(token) }
        guard let kind = WorkspaceTabCoding.entityKind(for: tab),
              let uuid = entityUUID(for: tab, using: ctx) else { return nil }
        return .entity(kind: kind, id: uuid)
    }

    private func entityUUID(for tab: WorkspaceTab, using ctx: ModelContext) -> UUID? {
        switch tab {
        case .project(let pid):     (ctx.model(for: pid) as? Project)?.id
        case .person(let pid):      (ctx.model(for: pid) as? Person)?.id
        case .institution(let pid): (ctx.model(for: pid) as? Institution)?.id
        case .minutes(let pid):     (ctx.model(for: pid) as? Minutes)?.id
        case .document(let pid):    (ctx.model(for: pid) as? Document)?.id
        case .contentNote(let pid): (ctx.model(for: pid) as? Note)?.id
        default:                    nil
        }
    }

    private func workspaceTab(for dest: TabDestination, using ctx: ModelContext) -> WorkspaceTab? {
        switch dest {
        case .page(let token):
            return WorkspaceTabCoding.categoryTab(forToken: token)
        case .entity(let kind, let id):
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
            default:
                return nil
            }
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

    /// Activate an existing tab already showing this destination, else open it in a new tab.
    func focusOrOpen(_ tab: WorkspaceTab) {
        if let existing = tabs.first(where: { $0.current == tab }) {
            activeId = existing.id
        } else {
            openInNewTab(tab)
        }
    }

    /// Focus a Diary tab on the given date and request a scroll to `noteId`. Reuses an existing
    /// Diary tab if one is open, otherwise navigates the active tab to the Diary.
    func focusDiary(date: Date, scrollTo noteId: UUID?) {
        let target = tabs.first { $0.current == .diary } ?? active
        if target.current != .diary { target.navigate(to: .diary) }
        activeId = target.id
        target.diaryState.mode = .day
        target.diaryState.goTo(date)
        target.diaryState.scrollTargetNoteId = noteId
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
        if tabs.isEmpty {
            let fallback = WorkspaceTabState(.diary)
            tabs = [fallback]
            activeId = fallback.id
        } else if activeId == id {
            activeId = tabs[min(idx, tabs.count - 1)].id
        }
    }

    /// Close any tab whose history references a now-deleted model id (call before deleting it).
    func closeEntity(_ id: PersistentIdentifier) {
        tabs.filter { $0.references(id) }.forEach { closeTab($0.id) }
    }
}
