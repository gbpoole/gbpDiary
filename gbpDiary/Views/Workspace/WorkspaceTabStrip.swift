import SwiftUI
import SwiftData

// Back/forward controls for the active tab, plus the strip of open tabs. Each tab shows the
// title of its current history location.
struct WorkspaceTabStrip: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        HStack(spacing: 8) {
            navButtons
            Divider().frame(height: 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(workspace.tabs) { tab in
                        tabChip(tab)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.background)
    }

    private var navButtons: some View {
        let active = workspace.active
        return HStack(spacing: 2) {
            Button { active.goBack() } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!active.canGoBack)
            .foregroundStyle(active.canGoBack ? AppTheme.text : AppTheme.mutedText)
            .help("Back")

            Button { active.goForward() } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!active.canGoForward)
            .foregroundStyle(active.canGoForward ? AppTheme.text : AppTheme.mutedText)
            .help("Forward")
        }
    }

    private func tabChip(_ tab: WorkspaceTabState) -> some View {
        let isActive = workspace.activeId == tab.id
        let info = describe(tab.current)
        let showClose = workspace.tabs.count > 1
        return HStack(spacing: 5) {
            Image(systemName: info.icon).font(.system(size: 10))
            Text(info.title).font(AppTheme.interfaceFont(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
            if showClose {
                Button { workspace.closeTab(tab.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.mutedText)
                .help("Close tab")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(isActive ? AppTheme.text : AppTheme.mutedText)
        .background(isActive ? AppTheme.cardRaised : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { workspace.activate(tab.id) }
    }

    private func describe(_ tab: WorkspaceTab) -> (title: String, icon: String) {
        switch tab {
        case .diary, .chat, .tasks, .projects, .people, .institutions,
             .meetings, .documents, .content, .images, .tags, .timesheet:
            let cat = tab.category
            return (cat.rawValue, cat.systemImage)
        case .contentNote(let pid):
            let title = model(pid, as: Note.self)?.title ?? ""
            return (title.isEmpty ? "Note" : title, "note.text")
        case .project(let pid):
            return (model(pid, as: Project.self)?.name ?? "Project", "folder")
        case .person(let pid):
            return (model(pid, as: Person.self)?.name ?? "Person", "person")
        case .institution(let pid):
            return (model(pid, as: Institution.self)?.name ?? "Institution", "building.2")
        case .minutes(let pid):
            return (model(pid, as: Minutes.self)?.summary ?? "Meeting", "person.3.sequence")
        case .document(let pid):
            return (model(pid, as: Document.self)?.summary ?? "Document", "doc")
        }
    }

    private func model<T: PersistentModel>(_ id: PersistentIdentifier, as _: T.Type) -> T? {
        modelContext.model(for: id) as? T
    }
}
