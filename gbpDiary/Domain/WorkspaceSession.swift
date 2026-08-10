import Foundation

// Codable session snapshot for the workspace: which tabs are open, each tab's browsing history +
// destination, the active tab, per-tab Diary date/mode, and every list page's filter/search/sort.
// Persisted to UserDefaults (see `WorkspaceSessionStore`) and rebuilt at launch by `WorkspaceModel`.
// Entity tabs are stored by the model's stable `@Attribute(.unique) var id` (UUID), not by
// `PersistentIdentifier`, so they survive relaunch and can be dropped cleanly if the entity is gone.

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
}

struct WorkspaceSnapshot: Codable, Equatable {
    var tabs: [TabSnapshot]
    var activeIndex: Int
}

// MARK: - WorkspaceTab <-> TabDestination (pure)

enum WorkspaceTabCoding {
    /// Token for a category/list-tool tab, or nil for entity tabs (which need a UUID).
    static func token(forCategoryTab tab: WorkspaceTab) -> String? {
        switch tab {
        case .diary:        "diary"
        case .chat:         "chat"
        case .tasks:        "tasks"
        case .projects:     "projects"
        case .people:       "people"
        case .institutions: "institutions"
        case .meetings:     "meetings"
        case .documents:    "documents"
        case .images:       "images"
        case .tags:         "tags"
        case .timesheet:    "timesheet"
        case .content:      "content"
        default:            nil
        }
    }

    static func categoryTab(forToken token: String) -> WorkspaceTab? {
        switch token {
        case "diary":        .diary
        case "chat":         .chat
        case "tasks":        .tasks
        case "projects":     .projects
        case "people":       .people
        case "institutions": .institutions
        case "meetings":     .meetings
        case "documents":    .documents
        case "images":       .images
        case "tags":         .tags
        case "timesheet":    .timesheet
        case "content":      .content
        default:             nil
        }
    }

    /// Token for an entity tab's kind, or nil for category tabs.
    static func entityKind(for tab: WorkspaceTab) -> String? {
        switch tab {
        case .project:     "project"
        case .person:      "person"
        case .institution: "institution"
        case .minutes:     "minutes"
        case .document:    "document"
        case .contentNote: "contentNote"
        default:           nil
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
