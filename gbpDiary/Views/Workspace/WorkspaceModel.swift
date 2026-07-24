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
    case tags
    case timesheet

    case project(PersistentIdentifier)
    case person(PersistentIdentifier)
    case institution(PersistentIdentifier)
    case minutes(PersistentIdentifier)
    case document(PersistentIdentifier)

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
        case .tags:                      .tags
        case .timesheet:                 .timesheet
        }
    }
}

// The fixed browse categories shown in the sidebar.
enum WorkspaceCategory: String, CaseIterable, Identifiable {
    case diary        = "Diary"
    case tasks        = "Tasks"
    case projects     = "Projects"
    case people       = "People"
    case institutions = "Institutions"
    case meetings     = "Meetings"
    case documents    = "Documents"
    case tags         = "Tags"
    case timesheet    = "Timesheet"

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
        case .tags:         .tags
        case .timesheet:    .timesheet
        }
    }
}

// One browsing pane: a back/forward history of destinations, like a browser tab. Sidebar
// selection and in-place drilldowns navigate within a single tab; only explicit "open in new
// tab" actions (e.g. meeting minutes) create another tab.
@Observable final class WorkspaceTabState: Identifiable {
    let id = UUID()
    // Per-tab Diary browsing state so two tabs showing the Diary can be on different dates.
    let diaryState = DiaryState()
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
                 .minutes(let x), .document(let x):
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
