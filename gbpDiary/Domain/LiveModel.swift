import SwiftData

extension ModelContext {
    /// Whether `id` still refers to a row that exists — the only test that holds AFTER a save.
    ///
    /// The three ways a model can be gone, and why the obvious checks aren't enough:
    ///   • **Before** the save that commits a delete: `isDeleted` is true, and the model sits in
    ///     `deletedModelsArray`.
    ///   • **After** that save: `deletedModelsArray` is cleared, `isDeleted` goes back to false and the
    ///     model still has a `modelContext` — so every in-memory signal says "alive" while reading any
    ///     stored property **traps** (SIGTRAP). This is the window that crashed the app twice.
    ///   • Deleted by someone else entirely (another context), where nothing local ever changed.
    ///
    /// Identity is the one thing that is always safe to read: `persistentModelID` never faults. So this
    /// compares the id against the ids that actually exist, using `fetchIdentifiers` so no row is
    /// materialised. Fails CLOSED — a wrong placeholder is recoverable, a crash is not.
    func isLive<T: PersistentModel>(_ id: PersistentIdentifier, as _: T.Type) -> Bool {
        if deletedModelsArray.contains(where: { $0.persistentModelID == id }) { return false }
        // A model inserted in this session isn't on disk yet but is perfectly alive (a brand-new meeting
        // being filled in, for instance).
        if insertedModelsArray.contains(where: { $0.persistentModelID == id }) { return true }
        guard let ids = try? fetchIdentifiers(FetchDescriptor<T>()) else { return false }
        return ids.contains(id)
    }

    /// Like `model(for:)` but nil when the id no longer refers to a live row. Any caller that renders a
    /// model's fields (tab-chip labels, detail views, the tab router) must go through this, or reading a
    /// dangling model's stored properties crashes the app.
    func liveModel<T: PersistentModel>(_ id: PersistentIdentifier, as type: T.Type) -> T? {
        guard isLive(id, as: type) else { return nil }
        return model(for: id) as? T
    }
}

extension PersistentModel {
    /// Whether this model has been deleted out from under a view that still holds it. Covers the in-memory
    /// signals (`ModelLiveness.isDead`) **and** the post-save window, where only identity can tell.
    ///
    /// A view holding a `@Bindable` model must check this before reading any of its fields: closing a tab
    /// doesn't unmount the view in the same pass, and a sheet isn't a tab at all.
    func isMissing(in context: ModelContext?) -> Bool {
        if isDeletedOrDetached { return true }
        guard let context else { return true }
        return !context.isLive(persistentModelID, as: Self.self)
    }
}
