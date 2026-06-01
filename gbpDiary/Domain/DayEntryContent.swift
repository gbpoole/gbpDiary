import Foundation

extension DayEntry {
    var inlineSummary: String {
        get {
            switch kind {
            case .note: return text
            case .task: return task?.summary ?? ""
            case .meeting: return minutes?.summary ?? ""
            }
        }
        set {
            switch kind {
            case .note: text = newValue
            case .task: task?.summary = newValue
            case .meeting: minutes?.summary = newValue.isEmpty ? nil : newValue
            }
        }
    }

    var isInlineSummaryEmpty: Bool {
        inlineSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Stable focus ID for this entry's inline notes/minutes sub-area.
    // Derived by bit-complementing entry.id — guaranteed distinct from any v4 UUID.
    var notesAreaFocusId: UUID { notesId(for: id) }
}

extension Task {
    // Stable focus ID for this task's inline notes sub-area in the diary.
    var notesAreaFocusId: UUID { notesId(for: id) }

    var isInlineSummaryEmpty: Bool {
        summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// Derives a "notes area" focus ID by bit-complementing every byte of the source UUID.
// UUID v4's reserved bits are inverted to values that standard generation never produces,
// so the result can never collide with an organically generated UUID.
// The function is its own inverse: notesId(notesId(x)) == x.
func notesId(for id: UUID) -> UUID {
    let (a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p) = id.uuid
    return UUID(uuid: (~a,~b,~c,~d,~e,~f,~g,~h,~i,~j,~k,~l,~m,~n,~o,~p))
}
