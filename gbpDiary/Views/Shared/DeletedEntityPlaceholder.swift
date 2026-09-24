import SwiftUI

// Shown in place of a detail view whose model has been deleted. A deleted entity's tab is closed by
// `WorkspaceModel.closeEntity`, but that cannot stop an already-mounted view from rendering once more
// in the same update pass — and a sheet is not a tab at all — so each detail view falls back to this
// rather than reading a tombstone's stored properties and trapping.
struct DeletedEntityPlaceholder: View {
    /// What was deleted, lowercase, e.g. "meeting" or "project".
    let noun: String

    var body: some View {
        ContentUnavailableView("Not available",
                               systemImage: "questionmark.folder",
                               description: Text("This \(noun) has been deleted."))
    }
}
