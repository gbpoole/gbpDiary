import Foundation
import SwiftData

// First-class provenance for a task: where it came from. One unified concept across capture sources —
// email (with a rich `EmailMessage` link), Slack/web (a deep-link `url`), or other. Owned by its `Task`
// (cascade: deleting the task deletes the source). For email, `email` gives the full message context
// (summary/importance/thread); `originEmail` on Task remains the email inverse backbone.
@Model final class TaskSource {
    @Attribute(.unique) var id: UUID
    private var kindRaw: String
    var url: String?          // deep link for slack/web/other (slack:// or https://…)
    var title: String?        // source title/label (e.g. the email subject, the page title)
    var createdAt: Date

    // The task this source belongs to (inverse declared on Task.source, which cascades).
    var task: Task?
    // Rich link for email captures; EmailMessage declares the inverse (`taskSources`) + nullify.
    var email: EmailMessage?

    var kind: TaskSourceKind {
        get { TaskSourceKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    init(kind: TaskSourceKind, url: String? = nil, title: String? = nil,
         email: EmailMessage? = nil, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.url = url
        self.title = title
        self.email = email
        self.createdAt = createdAt
    }
}
