import Foundation

// Bounds the ever-growing email store: a *dismissed* conversation whose latest message is older than the
// retention window is purged (with its messages) on launch, so triage stays fast. Accepted/to-triage
// conversations are kept regardless of age. Pure + testable; the @MainActor sweep lives in WorkspaceView.
nonisolated enum EmailRetention {
    static let dismissedDays = 30

    static func isPurgeable(dismissed: Bool, latestDate: Date?, now: Date = Date(),
                            days: Int = dismissedDays, calendar: Calendar = .current) -> Bool {
        guard dismissed, let latestDate else { return false }
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: now) else { return false }
        return latestDate < cutoff
    }
}
