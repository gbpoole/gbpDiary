import Foundation

nonisolated enum ChatSourceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case project
    case person
    case institution
    case note
    case meeting
    case task
    case document
    case email
    case day
    case attachment

    var displayName: String {
        switch self {
        case .project: "Project"
        case .person: "Person"
        case .institution: "Institution"
        case .note: "Note"
        case .meeting: "Meeting"
        case .task: "Task"
        case .document: "Document"
        case .email: "Email"
        case .day: "Diary"
        case .attachment: "Attachment"
        }
    }
}

nonisolated enum ChatNavigationKind: String, Codable, Hashable, Sendable {
    case project, person, institution, meeting, note, task, document, email, day, attachment
}

nonisolated struct ChatSourceKey: Codable, Hashable, Comparable, Sendable {
    let kind: ChatSourceKind
    let modelID: UUID

    var stableValue: String { "\(kind.rawValue):\(modelID.uuidString.lowercased())" }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableValue < rhs.stableValue }
}

nonisolated struct ChatSourceReference: Codable, Hashable, Sendable {
    let id: UUID
    let kind: ChatSourceKind
    var title: String
    var detail: String?
    var navigationKind: ChatNavigationKind
    var navigationID: UUID
    var navigationURL: URL?

    init(id: UUID, kind: ChatSourceKind, title: String, detail: String?,
         navigationKind: ChatNavigationKind? = nil, navigationID: UUID? = nil,
         navigationURL: URL? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.navigationKind = navigationKind ?? ChatNavigationKind(rawValue: kind.rawValue) ?? .note
        self.navigationID = navigationID ?? id
        self.navigationURL = navigationURL
    }

    var key: ChatSourceKey { ChatSourceKey(kind: kind, modelID: id) }

    var displayLabel: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? kind.displayName : "\(kind.displayName): \(trimmedTitle)"
    }
}

nonisolated struct ChatRetrievalDocument: Codable, Equatable, Identifiable, Sendable {
    var id: ChatSourceKey { source.key }
    var source: ChatSourceReference
    var markdown: String
    var summary: String?
    // Retrieval-scoping metadata (not shown to the user): the record's project names (lowercased) and a
    // representative date for recency ordering. Copied onto each chunk.
    var projectNames: [String]
    var sortDate: Date?
    // Manual email importance weight (0 = neutral; Medium 0.5, High 1.0). 0 for non-email sources.
    var importanceWeight: Double

    init(source: ChatSourceReference, markdown: String, summary: String? = nil,
         projectNames: [String] = [], sortDate: Date? = nil, importanceWeight: Double = 0) {
        self.source = source
        self.markdown = markdown
        self.summary = summary
        self.projectNames = projectNames
        self.sortDate = sortDate
        self.importanceWeight = importanceWeight
    }
}

nonisolated struct ChatRetrievalChunk: Codable, Equatable, Identifiable, Sendable {
    /// Stable while the source and deterministic chunking configuration are unchanged.
    let id: String
    let source: ChatSourceReference
    let index: Int
    let text: String
    let projectNames: [String]
    let sortDate: Date?
    let importanceWeight: Double

    init(source: ChatSourceReference, index: Int, text: String,
         projectNames: [String] = [], sortDate: Date? = nil, importanceWeight: Double = 0) {
        id = "\(source.key.stableValue):\(index)"
        self.source = source
        self.index = index
        self.text = text
        self.projectNames = projectNames
        self.sortDate = sortDate
        self.importanceWeight = importanceWeight
    }
}
