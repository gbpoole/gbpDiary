import Foundation

@Observable final class MinutesEditorContext {
    private(set) var stack: [(note: Note, title: String?)] = []

    var activeNote: Note? { stack.last?.note }
    var activeTitle: String? { stack.last?.title }
    var canGoBack: Bool { stack.count > 1 }

    func open(note: Note, title: String?) {
        if let idx = stack.firstIndex(where: { $0.note.id == note.id }) {
            let entry = stack.remove(at: idx)
            stack.append((note: entry.note, title: title ?? entry.title))
        } else {
            stack.append((note: note, title: title))
        }
    }

    func back() {
        guard stack.count > 1 else { return }
        stack.removeLast()
    }

    func remove(note: Note) {
        stack.removeAll { $0.note.id == note.id }
    }

    func close() { stack.removeAll() }
}
