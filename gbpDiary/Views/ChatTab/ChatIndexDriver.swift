import SwiftUI
import SwiftData

/// Keeps the rebuildable local sidecar aligned with source deletion/dismissal even when Chat is idle.
struct ChatIndexDriver: View {
    @Query private var projects: [Project]
    @Query private var tasks: [Task]
    @Query private var people: [Person]
    @Query private var institutions: [Institution]
    @Query private var meetings: [Minutes]
    @Query private var notes: [Note]
    @Query private var days: [DayRecord]
    @Query private var documents: [Document]
    @Query private var emails: [EmailMessage]
    @Query private var attachments: [Attachment]

    private let worker = ChatRetrievalWorker.shared

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: sourceRevision) {
                guard let url = try? ChatSemanticIndex.defaultURL() else { return }
                let snapshot = ChatCorpusBuilder().snapshot(
                    projects: projects, tasks: tasks, people: people, institutions: institutions,
                    meetings: meetings, notes: notes, days: days, documents: documents,
                    emails: emails, attachments: attachments)
                _ = await worker.rebuild(snapshot: snapshot, indexURL: url)
            }
    }

    /// Includes content timestamps plus privacy-relevant membership, so deletes and email dismissal
    /// promptly remove sources. Chat queries still fingerprint every projected field before reuse.
    private var sourceRevision: Int {
        var hasher = Hasher()
        for value in projects.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(value.id); hasher.combine(value.updatedAt)
        }
        for value in tasks.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(value.id); hasher.combine(value.updatedAt)
        }
        for value in people.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(value.id); hasher.combine(value.updatedAt)
        }
        for value in institutions.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(value.id); hasher.combine(value.updatedAt)
        }
        for value in meetings.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(value.id); hasher.combine(value.updatedAt)
        }
        for value in notes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(value.id); hasher.combine(value.updatedAt)
        }
        for value in days.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(value.id); hasher.combine(value.updatedAt)
        }
        for value in documents.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(value.id); hasher.combine(value.updatedAt)
        }
        for value in emails.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(value.id); hasher.combine(value.dismissed)
            hasher.combine(value.summary); hasher.combine(value.summaryPromptVersion)
        }
        for value in attachments.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(value.id); hasher.combine(value.fileURL)
            hasher.combine(value.fileSizeBytes); hasher.combine(value.attachmentDescription)
        }
        return hasher.finalize()
    }
}
