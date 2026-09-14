import Foundation

// Where a task came from — the unified provenance concept (see `TaskSource`). Email additionally carries a
// rich `EmailMessage` relationship; slack/web carry a deep link (`TaskSource.url`).
nonisolated enum TaskSourceKind: String, Codable, CaseIterable, Sendable {
    case email
    case slack
    case web
    case other

    var displayName: String {
        switch self {
        case .email: "Email"
        case .slack: "Slack"
        case .web:   "Web"
        case .other: "Link"
        }
    }

    var systemImage: String {
        switch self {
        case .email: "envelope"
        case .slack: "message"
        case .web:   "globe"
        case .other: "link"
        }
    }
}
