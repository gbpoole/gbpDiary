import SwiftData

extension ModelContext {
    /// Like `model(for:)` but returns nil when the id refers to a model deleted in this session. Such a
    /// model still resolves via `model(for:)`, but reading its stored properties **traps** in SwiftData —
    /// so any caller that renders a model's fields (tab-chip labels, detail views) must exclude it, or the
    /// app crashes (SIGTRAP). `persistentModelID` never faults, so scanning pending deletions is safe.
    func liveModel<T: PersistentModel>(_ id: PersistentIdentifier, as _: T.Type) -> T? {
        if deletedModelsArray.contains(where: { $0.persistentModelID == id }) { return nil }
        return model(for: id) as? T
    }
}
