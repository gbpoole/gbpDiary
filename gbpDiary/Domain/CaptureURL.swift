import Foundation

// Parses the `gbpdiary://task?…` capture URL into a structured request. Driven by Alfred/Shortcuts (or a raw
// `open`), it carries what a captured task needs; the app resolves `mailId` to an `EmailMessage` for email
// captures. Pure + testable — no side effects.
nonisolated enum CaptureURL {
    struct Request: Equatable {
        var title: String?
        var kind: TaskSourceKind
        var url: String?
        var mailId: String?     // Mail's integer message id (as text) when kind == .email
    }

    /// `gbpdiary://task?title=…&kind=email|slack|web|other&url=…&mailId=…`. Returns nil for a wrong scheme,
    /// a non-`task` action, or a request with no usable content (needs at least a title, url, or mailId).
    static func parse(_ url: URL) -> Request? {
        guard url.scheme?.lowercased() == "gbpdiary" else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // Accept the action as the host (`gbpdiary://task?…`) or the first path element.
        let action = (comps?.host ?? url.pathComponents.first { $0 != "/" })?.lowercased()
        guard action == "task" else { return nil }

        let items = comps?.queryItems ?? []
        func value(_ name: String) -> String? {
            let raw = items.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty ?? true) ? nil : raw
        }

        let kind = value("kind").flatMap { TaskSourceKind(rawValue: $0.lowercased()) } ?? .other
        let request = Request(title: value("title"), kind: kind, url: value("url"), mailId: value("mailId"))
        guard request.title != nil || request.url != nil || request.mailId != nil else { return nil }
        return request
    }
}
