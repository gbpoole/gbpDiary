import Foundation

// One-time migration to first-class provenance: every task made from an email (legacy `originEmail`) that
// doesn't yet have a `source` gets an email `TaskSource`. Pure planner; the @MainActor applier in
// WorkspaceView creates the `TaskSource(kind: .email, email:)` and links it. Idempotent by design — a task
// with a source is skipped, so re-runs plan nothing.
nonisolated enum TaskSourceMigration {
    struct Input: Equatable {
        let taskID: UUID
        let hasSource: Bool
        let hasOriginEmail: Bool
    }

    /// Task ids needing an email `TaskSource` created: those with a legacy `originEmail` and no `source` yet.
    static func plan(_ inputs: [Input]) -> [UUID] {
        inputs.filter { $0.hasOriginEmail && !$0.hasSource }.map(\.taskID)
    }
}
