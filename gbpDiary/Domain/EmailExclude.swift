import Foundation

// User-managed spam rules: emails matching a rule are auto-dismissed on ingest (future-only — existing
// emails are untouched). A rule matches either the SENDER (a full address "noreply@x.com" or a domain
// "x.com"/"@x.com") or the SUBJECT (any subject containing the text, e.g. "[lsc-all]"). Pure matching
// is testable; the list persists in UserDefaults (with a one-time migration of the legacy sender list).

enum EmailExcludeField: String, Codable, CaseIterable {
    case sender
    case subject
    var label: String { self == .sender ? "Sender" : "Subject" }
}

struct EmailExcludeRule: Codable, Equatable, Identifiable {
    var field: EmailExcludeField
    var pattern: String          // normalised: sender lowercased; subject as typed (matched case-insensitively)
    var id: String { "\(field.rawValue)|\(pattern)" }
}

enum EmailExcludeMatching {
    /// True when the email matches any rule.
    static func isExcluded(fromAddress: String, subject: String, rules: [EmailExcludeRule]) -> Bool {
        rules.contains { matches(fromAddress: fromAddress, subject: subject, rule: $0) }
    }

    static func matches(fromAddress: String, subject: String, rule: EmailExcludeRule) -> Bool {
        switch rule.field {
        case .sender:  return senderMatches(fromAddress, rule.pattern)
        case .subject: return subjectMatches(subject, rule.pattern)
        }
    }

    /// Sender rule: full-address or domain match (case-insensitive, whitespace-trimmed).
    static func senderMatches(_ address: String, _ pattern: String) -> Bool {
        let addr = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let rule = normalize(pattern), !addr.isEmpty else { return false }
        let domain = addr.split(separator: "@").last.map(String.init) ?? ""
        if rule.contains("@"), !rule.hasPrefix("@") {
            return addr == rule                                   // full-address rule
        }
        let ruleDomain = rule.hasPrefix("@") ? String(rule.dropFirst()) : rule
        return !ruleDomain.isEmpty && domain == ruleDomain        // domain rule
    }

    /// Subject rule: case-insensitive substring match (so "[lsc-all]" catches "Re: [lsc-all] …" too).
    static func subjectMatches(_ subject: String, _ pattern: String) -> Bool {
        let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !p.isEmpty else { return false }
        return subject.lowercased().contains(p)
    }

    /// Trim (+ lowercase for sender) a raw pattern for storage; nil when blank.
    static func normalizePattern(_ raw: String, field: EmailExcludeField) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return field == .sender ? t.lowercased() : t
    }

    /// Legacy helper kept for the settings "Add" enable check.
    static func normalize(_ raw: String) -> String? { normalizePattern(raw, field: .sender) }

    /// Sender rules to suggest for a given address: the full address, and its domain.
    static func suggestions(forAddress address: String) -> [String] {
        guard let a = normalize(address), a.contains("@") else { return [] }
        let domain = a.split(separator: "@").last.map(String.init) ?? ""
        return domain.isEmpty ? [a] : [a, "@\(domain)"]
    }
}

enum EmailExcludeStore {
    private static let rulesKey = "email.excludeRules"
    private static let legacyKey = "email.excludeSenders"   // old [String] of sender patterns

    static func load(_ d: UserDefaults = .standard) -> [EmailExcludeRule] {
        if let data = d.data(forKey: rulesKey),
           let rules = try? JSONDecoder().decode([EmailExcludeRule].self, from: data) {
            return rules
        }
        // One-time migration of the legacy sender-only string list into typed rules.
        let migrated = (d.stringArray(forKey: legacyKey) ?? []).compactMap { raw -> EmailExcludeRule? in
            EmailExcludeMatching.normalizePattern(raw, field: .sender).map { EmailExcludeRule(field: .sender, pattern: $0) }
        }
        if !migrated.isEmpty { save(migrated, d) }
        return migrated
    }

    static func save(_ rules: [EmailExcludeRule], _ d: UserDefaults = .standard) {
        d.set((try? JSONEncoder().encode(rules)) ?? Data(), forKey: rulesKey)
    }

    /// Add a rule (normalised, deduped by id). No-op on blank/duplicate.
    static func add(field: EmailExcludeField, pattern: String, _ d: UserDefaults = .standard) {
        guard let p = EmailExcludeMatching.normalizePattern(pattern, field: field) else { return }
        let rule = EmailExcludeRule(field: field, pattern: p)
        var rules = load(d)
        guard !rules.contains(where: { $0.id == rule.id }) else { return }
        rules.append(rule)
        save(rules, d)
    }

    /// Convenience for the triage "exclude sender / domain" quick action.
    static func addSender(_ pattern: String, _ d: UserDefaults = .standard) {
        add(field: .sender, pattern: pattern, d)
    }

    static func remove(_ rule: EmailExcludeRule, _ d: UserDefaults = .standard) {
        save(load(d).filter { $0.id != rule.id }, d)
    }
}
