import Foundation

// Codable session snapshot for the workspace: the selected sidebar category, the open **entity** tabs,
// which (if any) is active, the Diary date/mode, and every list page's filter/search/sort.
// Persisted to UserDefaults (see `WorkspaceSessionStore`) and rebuilt at launch by `WorkspaceModel`.
// Entity tabs are stored by the model's stable `@Attribute(.unique) var id` (UUID), not by
// `PersistentIdentifier`, so they survive relaunch and can be dropped cleanly if the entity is gone.
//
// **Two shapes live here.** Sessions written before browse categories became fixed panes stored a list of
// tabs, each with its own history and its own copy of the page state. Those fields are kept, decode-only,
// and `WorkspaceSnapshot.migrated()` folds them into the current shape — otherwise every existing session
// would fail to decode and silently reset.

/// Codable mirror of a `WorkspaceTab` destination.
enum TabDestination: Codable, Equatable {
    case page(String)                     // category/list-tool tab token (see WorkspaceTabCoding)
    case entity(kind: String, id: UUID)   // entity kind token + the model's UUID
}

struct DiarySnapshot: Codable, Equatable {
    var date: Date
    var mode: String
    var tracksToday: Bool
}

struct ListFilterSnapshot: Codable, Equatable {
    var activeFilterIds: [String]
    var searchText: String
    var sortColumnID: String
    var sortAscending: Bool
}

struct TasksFilterSnapshot: Codable, Equatable {
    var activeFilterIds: [String]
    var searchText: String
    var sortColumnID: String
    var sortAscending: Bool
    var dateRangeStart: Date?
    var dateRangeEnd: Date?
    var datePreset: String?
}

struct TabSnapshot: Codable, Equatable {
    var history: [TabDestination]
    var index: Int
    var diary: DiarySnapshot
    var tasksFilter: TasksFilterSnapshot
    var pageFilters: [String: ListFilterSnapshot]   // key = WorkspaceCategory.rawValue
    /// Whether this tab's planning-board panel is open. **Optional on purpose**: sessions written
    /// before the board became a panel have no such key, and a required field would fail to decode —
    /// taking every tab with it. Absent means "closed".
    var boardPanelShown: Bool?
    /// Also optional, for the same reason: sessions written before full-width existed have no such key.
    var boardFullWidth: Bool?
}

/// One open entity tab. Nothing else is persisted about a tab: it shows one entity, and `curationIndex`
/// is deliberately session-only (the walk is recomputed from live data).
struct EntityTabSnapshot: Codable, Equatable {
    var kind: String
    var id: UUID
}

struct WorkspaceSnapshot: Codable, Equatable {
    // MARK: Current shape (all optional so a legacy payload still decodes)
    var selectedCategory: String?
    var entityTabs: [EntityTabSnapshot]?
    /// Index into `entityTabs`, or nil while the selected category's pane is showing.
    var activeTabIndex: Int?
    var diary: DiarySnapshot?
    var tasksFilter: TasksFilterSnapshot?
    var pageFilters: [String: ListFilterSnapshot]?
    var boardPanelShown: Bool?
    var boardFullWidth: Bool?

    // MARK: Legacy shape (decode-only; see `migrated()`)
    var tabs: [TabSnapshot]?
    var activeIndex: Int?

    init(selectedCategory: String? = nil, entityTabs: [EntityTabSnapshot]? = nil,
         activeTabIndex: Int? = nil, diary: DiarySnapshot? = nil,
         tasksFilter: TasksFilterSnapshot? = nil, pageFilters: [String: ListFilterSnapshot]? = nil,
         boardPanelShown: Bool? = nil, boardFullWidth: Bool? = nil,
         tabs: [TabSnapshot]? = nil, activeIndex: Int? = nil) {
        self.selectedCategory = selectedCategory
        self.entityTabs = entityTabs
        self.activeTabIndex = activeTabIndex
        self.diary = diary
        self.tasksFilter = tasksFilter
        self.pageFilters = pageFilters
        self.boardPanelShown = boardPanelShown
        self.boardFullWidth = boardFullWidth
        self.tabs = tabs
        self.activeIndex = activeIndex
    }

    /// Whether this payload predates fixed category panes.
    var isLegacy: Bool { entityTabs == nil && !(tabs ?? []).isEmpty }

    /// Fold a legacy snapshot into the current shape. Pure, so the rules are testable:
    /// - the **selected category** is the one the active tab was showing (a page token); `.diary` otherwise;
    /// - the **entity tabs** are the entities each old tab was *currently* showing, deduped and in tab
    ///   order — histories are dropped, since resurrecting pages you had navigated away from would reopen
    ///   work you closed;
    /// - the **active tab** is the old active tab's entity, or nil (pane) when it was showing a category;
    /// - the page state (diary, tasks filter, list filters, board) comes from the **active** tab, that
    ///   being the only defensible single choice among per-tab copies.
    func migrated() -> WorkspaceSnapshot {
        guard isLegacy, let legacyTabs = tabs, !legacyTabs.isEmpty else { return self }
        let activeIdx = min(max(0, activeIndex ?? 0), legacyTabs.count - 1)
        let activeTab = legacyTabs[activeIdx]
        let activeCurrent = activeTab.history.indices.contains(activeTab.index)
            ? activeTab.history[activeTab.index] : activeTab.history.last

        var category = WorkspaceCategory.diary.rawValue
        if case .page(let token) = activeCurrent,
           let resolved = WorkspaceTabCoding.categoryToken(migrating: token) {
            category = resolved
        }

        var entities: [EntityTabSnapshot] = []
        var activeEntityIndex: Int?
        for (offset, tab) in legacyTabs.enumerated() {
            let current = tab.history.indices.contains(tab.index) ? tab.history[tab.index] : tab.history.last
            guard case .entity(let kind, let id) = current else { continue }
            let snap = EntityTabSnapshot(kind: kind, id: id)
            let existing = entities.firstIndex(of: snap)
            let position = existing ?? entities.count
            if existing == nil { entities.append(snap) }
            if offset == activeIdx { activeEntityIndex = position }
        }

        return WorkspaceSnapshot(
            selectedCategory: category,
            entityTabs: entities,
            activeTabIndex: activeEntityIndex,
            diary: activeTab.diary,
            tasksFilter: activeTab.tasksFilter,
            pageFilters: activeTab.pageFilters,
            boardPanelShown: activeTab.boardPanelShown,
            boardFullWidth: activeTab.boardFullWidth)
    }
}

// MARK: - WorkspaceTab <-> TabDestination (pure)

enum WorkspaceTabCoding {
    /// Resolve a legacy page token to a `WorkspaceCategory.rawValue`, or nil if it names nothing we have.
    /// The token set is the old tab vocabulary, which is why `"board"` appears: the board used to be its
    /// own tab, and it now lives in the Tasks page's panel.
    static func categoryToken(migrating token: String) -> String? {
        switch token {
        case "diary":          WorkspaceCategory.diary.rawValue
        case "chat":           WorkspaceCategory.chat.rawValue
        case "triage":         WorkspaceCategory.triage.rawValue
        case "tasks", "board": WorkspaceCategory.tasks.rawValue
        case "projects":       WorkspaceCategory.projects.rawValue
        case "people":         WorkspaceCategory.people.rawValue
        case "institutions":   WorkspaceCategory.institutions.rawValue
        case "meetings":       WorkspaceCategory.meetings.rawValue
        case "documents":      WorkspaceCategory.documents.rawValue
        case "images":         WorkspaceCategory.images.rawValue
        case "tags":           WorkspaceCategory.tags.rawValue
        case "timesheet":      WorkspaceCategory.timesheet.rawValue
        case "content":        WorkspaceCategory.content.rawValue
        default:               nil
        }
    }

    /// Token for an entity tab's kind. Every tab is an entity now, so this is total.
    static func entityKind(for tab: WorkspaceTab) -> String {
        switch tab {
        case .project:       "project"
        case .person:        "person"
        case .institution:   "institution"
        case .minutes:       "minutes"
        case .document:      "document"
        case .contentNote:   "contentNote"
        case .task:          "task"
        case .curation:      "curation"
        case .emailExplorer: "emailExplorer"
        }
    }
}

// MARK: - Store

/// Persists the workspace session snapshot as JSON in UserDefaults (mirrors AppSettingsStore).
enum WorkspaceSessionStore {
    private static let key = "workspaceSession"

    static var snapshot: WorkspaceSnapshot? {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
