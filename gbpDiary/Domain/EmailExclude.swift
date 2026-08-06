import Foundation

// A user-managed exclude list: emails whose sender/recipient address matches a rule are auto-dismissed
// on ingest (future-only — existing emails are untouched). A rule is either a full address
// ("noreply@x.com") or a domain ("x.com" or "@x.com"). Pure matching is testable; the list persists
// in UserDefaults.
enum EmailExcludeMatching {
    /// True when `address` matches any rule (case-insensitive, whitespace-trimmed).
    static func isExcluded(address: String, rules: [String]) -> Bool {
        let addr = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !addr.isEmpty else { return false }
        let domain = addr.split(separator: "@").last.map(String.init) ?? ""
        for raw in rules {
            guard let rule = normalize(raw) else { continue }
            if rule.contains("@"), !rule.hasPrefix("@") {
                if addr == rule { return true }                 // full-address rule
            } else {
                let ruleDomain = rule.hasPrefix("@") ? String(rule.dropFirst()) : rule
                if !ruleDomain.isEmpty, domain == ruleDomain { return true }   // domain rule
            }
        }
        return false
    }

    /// Trim + lowercase a raw rule for storage/matching; nil when blank.
    static func normalize(_ raw: String) -> String? {
        let r = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return r.isEmpty ? nil : r
    }

    /// The exclude rule to suggest for a given address: the full address, and its domain.
    static func suggestions(forAddress address: String) -> [String] {
        guard let a = normalize(address), a.contains("@") else { return [] }
        let domain = a.split(separator: "@").last.map(String.init) ?? ""
        return domain.isEmpty ? [a] : [a, "@\(domain)"]
    }
}

enum EmailExcludeStore {
    private static let key = "email.excludeSenders"

    static func load(_ d: UserDefaults = .standard) -> [String] {
        d.stringArray(forKey: key) ?? []
    }

    static func save(_ rules: [String], _ d: UserDefaults = .standard) {
        d.set(rules, forKey: key)
    }

    /// Add a normalised rule (deduped, case-insensitive). No-op on blank/duplicate.
    static func add(_ rule: String, _ d: UserDefaults = .standard) {
        guard let r = EmailExcludeMatching.normalize(rule) else { return }
        var rules = load(d)
        guard !rules.contains(r) else { return }
        rules.append(r)
        save(rules, d)
    }

    static func remove(_ rule: String, _ d: UserDefaults = .standard) {
        let r = EmailExcludeMatching.normalize(rule)
        save(load(d).filter { $0 != r }, d)
    }
}
