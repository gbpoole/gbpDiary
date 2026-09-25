import SwiftUI

// How a lane looks, in one place — used by the board's lane headers AND by the Tasks table's marker,
// so the two surfaces teach the same vocabulary and cannot drift apart.
//
// Shape carries the meaning as much as colour does: three tints alone would be a colour-only code,
// which is both ambiguous and inaccessible.
extension PlanHorizon {
    var systemImage: String {
        switch self {
        case .today:    "sun.max"
        case .thisWeek: "calendar"
        case .maybe:    "questionmark.circle"
        }
    }

    /// Also used as the Tasks table's summary TEXT colour, so it must be legible against the dark
    /// background and clearly distinct from `AppTheme.text` — muted grey would read as no signal at all.
    var tint: Color {
        switch self {
        case .today:    AppTheme.today          // green
        case .thisWeek: AppTheme.accent         // yellow
        case .maybe:    AppTheme.Kanagawa.mauve // distinct and lower-energy, but still readable
        }
    }
}
