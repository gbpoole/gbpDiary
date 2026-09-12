import Foundation

// Corrective one-time migration: the Obsidian import named each focus block's backing task after the
// PROJECT and stored the real activity description in the block's `comment`. This re-points each described
// block onto a task named after its description (one task per (project, description) group — repeated days
// share it), preserving the block itself so its net-capacity behavior is unchanged. `plan` is the pure
// grouping; the @MainActor applier in WorkspaceView creates the tasks and re-points the blocks.
nonisolated enum FocusBlockDescriptionMigration {
    struct Input: Equatable {
        let blockID: UUID
        let description: String?
        let projectID: UUID?

        init(blockID: UUID, description: String?, projectID: UUID?) {
            self.blockID = blockID
            self.description = description
            self.projectID = projectID
        }
    }

    struct Group: Equatable {
        let projectID: UUID?
        let description: String   // trimmed, non-empty — becomes the task summary
        let blockIDs: [UUID]
    }

    /// One Group per (projectID, trimmed non-empty description). Blocks with a blank/nil description are
    /// omitted (they keep their current backing task). Deterministic: groups and their block ids preserve
    /// input order.
    static func plan(_ inputs: [Input]) -> [Group] {
        struct Key: Hashable { let projectID: UUID?; let description: String }
        var order: [Key] = []
        var blocksByKey: [Key: [UUID]] = [:]
        var descriptionByKey: [Key: String] = [:]
        for input in inputs {
            guard let raw = input.description else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = Key(projectID: input.projectID, description: trimmed)
            if blocksByKey[key] == nil {
                order.append(key)
                descriptionByKey[key] = trimmed
            }
            blocksByKey[key, default: []].append(input.blockID)
        }
        return order.map { Group(projectID: $0.projectID, description: descriptionByKey[$0] ?? $0.description,
                                 blockIDs: blocksByKey[$0] ?? []) }
    }
}
