import Foundation
import SwiftData

// A single open tab in the workspace. Category tabs are singletons; entity tabs carry the
// entity's stable `PersistentIdentifier` so the same entity re-opens/activates one tab.
enum WorkspaceTab: Hashable, Identifiable {
    case diary
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

// One browsing pane: a back/forward history of destinations, like a browser tab. Sidebar
// selection and in-place drilldowns navigate within a single tab; only explicit "open in new
// tab" actions (e.g. meeting minutes) create another tab.
// Per-tab Tasks-page filter state, so filters are remembered when you navigate away and back, and two
// tabs can hold different Tasks filters at once.
@Observable final class TasksFilterState {
    var activeFilterIds: Set<String> = []
    var dateRange: ClosedRange<Date>? = nil
    var sortMode: TaskSortMode = .urgency
}

@Observable final class WorkspaceTabState: Identifiable {
    let id = UUID()
    // Per-tab Diary browsing state so two tabs showing the Diary can be on different dates.
    let diaryState = DiaryState()
    // Per-tab Tasks-page filter state (remembered across in-tab navigation).
    let tasksFilter = TasksFilterState()
    private(set) var history: [WorkspaceTab]
    private(set) var index: Int

    var current: WorkspaceTab { history[index] }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < history.count - 1 }

    init(_ tab: WorkspaceTab) {
        history = [tab]
        index = 0
    }

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

    func activate(_ id: UUID) { activeId = id }

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
