import SwiftData

// Whether a SwiftData model is still safe to read.
//
// A deleted model keeps resolving, but reading its STORED properties traps (SIGTRAP) — the crash this
// exists to prevent. Detecting it needs both signals, because each covers only half the window
// (measured, see ModelLivenessTests):
//
//   • `isDeleted` is true only BEFORE the save that commits the deletion; after the save it reverts to
//     false.
//   • `modelContext` becomes nil only AFTER that save; before it, the model still has its context.
//
// `ModelContext.liveModel` (Domain/LiveModel.swift) covers the pre-save window only — it scans
// `deletedModelsArray`, which SwiftData clears on save — so it is right for resolving an id to a model
// (the tab router) but NOT for a view already holding one.
enum ModelLiveness {
    /// Pure decision: dead if SwiftData flags it deleted, or it has been detached from its context.
    static func isDead(isDeleted: Bool, hasContext: Bool) -> Bool {
        isDeleted || !hasContext
    }
}

extension PersistentModel {
    /// True once this model has been deleted, in either the pre- or post-save window. Safe to read on a
    /// tombstone: neither `isDeleted` nor `modelContext` is a stored attribute, so neither faults.
    ///
    /// NOTE: a model that was never inserted into a context also reports true, since it likewise has no
    /// context. Views must be handed inserted models (all current callers are).
    var isDeletedOrDetached: Bool {
        ModelLiveness.isDead(isDeleted: isDeleted, hasContext: modelContext != nil)
    }
}
