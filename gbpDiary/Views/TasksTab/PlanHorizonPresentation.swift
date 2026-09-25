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
    ///
    /// The tints run hottest to coolest with urgency, continuing the ramp the derived Due & overdue
    /// cards already start: red (overdue) → peach (due today) → **yellow (Today)** → **green (This
    /// Week)** → mauve (Maybe). Note this means the Today lane is deliberately NOT `AppTheme.today`,
    /// which is green; the lane colours encode urgency, not the app's day accent.
    var tint: Color {
        switch self {
        case .today:    AppTheme.Kanagawa.yellow // warmest of the three — act now
        case .thisWeek: AppTheme.Kanagawa.green  // cooler — soon, but not today
        case .maybe:    AppTheme.Kanagawa.mauve  // coolest, still readable
        }
    }
}
