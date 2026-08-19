import SwiftUI
import SwiftData

// Back/forward controls for the active tab, plus the strip of open tabs. Each tab shows the
// title of its current history location.
struct WorkspaceTabStrip: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceModel.self) private var workspace
    // Index of the chip a drag is currently hovering (an insertion marker); `tabs.count` = the trailing
    // append zone.
    @State private var dropTargetIndex: Int?

    var body: some View {
        HStack(spacing: 8) {
            navButtons
            Divider().frame(height: 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(workspace.tabs.enumerated()), id: \.element.id) { index, tab in
                        tabChip(tab, index: index)
                    }
                    trailingDropZone
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.background)
    }

    // Drops here append the dragged tab to the end of the strip.
    private var trailingDropZone: some View {
        Color.clear
            .frame(width: 12, height: 22)
            .overlay(alignment: .leading) { insertionMarker(at: workspace.tabs.count) }
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items, toIndex: workspace.tabs.count)
            } isTargeted: { targeted in
                dropTargetIndex = targeted ? workspace.tabs.count : (dropTargetIndex == workspace.tabs.count ? nil : dropTargetIndex)
            }
    }

    // A 2pt accent bar shown on the leading edge of the chip a drag is hovering (insert-before marker).
    @ViewBuilder
    private func insertionMarker(at index: Int) -> some View {
        if dropTargetIndex == index {
            RoundedRectangle(cornerRadius: 1).fill(AppTheme.accent).frame(width: 2)
        }
    }

    private func handleDrop(_ items: [String], toIndex: Int) -> Bool {
        dropTargetIndex = nil
        guard let first = items.first, let draggedId = UUID(uuidString: first) else { return false }
        workspace.moveTab(id: draggedId, toIndex: toIndex)
        workspace.save(using: modelContext)   // persist the new order immediately
        return true
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

    private func tabChip(_ tab: WorkspaceTabState, index: Int) -> some View {
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
        .overlay(alignment: .leading) { insertionMarker(at: index) }
        .contentShape(Rectangle())
        .onTapGesture { workspace.activate(tab.id) }
        // Drag to reorder: carry the tab id; dropping onto a chip inserts before it.
        .draggable(tab.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items, toIndex: index)
        } isTargeted: { targeted in
            dropTargetIndex = targeted ? index : (dropTargetIndex == index ? nil : dropTargetIndex)
        }
    }

    private func describe(_ tab: WorkspaceTab) -> (title: String, icon: String) {
        switch tab {
        case .diary, .chat, .triage, .tasks, .projects, .people, .institutions,
             .meetings, .documents, .content, .images, .tags, .timesheet:
            let cat = tab.category
            return (cat.title, cat.systemImage)
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
