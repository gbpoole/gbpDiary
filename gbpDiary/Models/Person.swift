import Foundation
import SwiftData

@Model final class Person {
    @Attribute(.unique) var id: UUID
    var name: String
    /// LEGACY: migrated into `emails` on first launch, then set nil. Do not read in UI — use `primaryEmail`.
    var email: String?
    /// Default at the property level so SwiftData can lightweight-migrate existing stores.
    var emailsJSON: String = "[]"
    /// Ordered list of email addresses; the first is the primary (used wherever one email is needed).
    var emails: [String] {
        get { jsonDecode([String].self, emailsJSON) ?? [] }
        set { emailsJSON = jsonEncode(newValue) }
    }
    var primaryEmail: String? { emails.first }
    var tagsJSON: String
    var tags: [String] {
        get { jsonDecode([String].self, tagsJSON) ?? [] }
        set { tagsJSON = jsonEncode(newValue) }
    }
    var createdAt: Date
    var updatedAt: Date

    var institution: Institution?
    var devProjects: [Project]
    var sciProjects: [Project]
    var minutesAttended: [Minutes]
    @Relationship(deleteRule: .nullify, inverse: \Task.assignee) var tasks: [Task]
    @Relationship(deleteRule: .nullify, inverse: \EmailMessage.person) var emailMessages: [EmailMessage]

    init(name: String, id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.emailsJSON = "[]"
        self.tagsJSON = "[]"
        self.devProjects = []
        self.sciProjects = []
        self.minutesAttended = []
        self.tasks = []
        self.emailMessages = []
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }
}

extension Person {
    /// Case-insensitive append that preserves order (and the existing primary); no-op if the
    /// email is already present or blank.
    static func appendingEmail(_ email: String, to existing: [String]) -> [String] {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty else { return existing }
        if existing.contains(where: { $0.caseInsensitiveCompare(e) == .orderedSame }) { return existing }
        return existing + [e]
    }

    /// One-time migration: the emails list a legacy Person should have, or nil when no migration
    /// is needed (already has emails, or the legacy field is nil/blank).
    static func migratedEmails(legacyEmail: String?, existingEmails: [String]) -> [String]? {
        guard existingEmails.isEmpty,
              let e = legacyEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !e.isEmpty else { return nil }
        return [e]
    }
}
