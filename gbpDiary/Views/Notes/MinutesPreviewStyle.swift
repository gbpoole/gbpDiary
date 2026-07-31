import SwiftUI
import Textual

// A Textual heading style for the minutes preview: each heading level gets a distinct colour from the
// app's Kanagawa palette (plus size/weight), so meeting minutes read with clear visual hierarchy.
struct MinutesHeadingStyle: StructuredText.HeadingStyle {
    private static let scales: [CGFloat] = [1.9, 1.55, 1.3, 1.12, 1.0, 0.9]
    private static let colors: [Color] = [
        AppTheme.Kanagawa.sapphire,   // H1
        AppTheme.Kanagawa.teal,       // H2
        AppTheme.Kanagawa.green,      // H3
        AppTheme.Kanagawa.mauve,      // H4
        AppTheme.Kanagawa.peach,      // H5
        AppTheme.Kanagawa.subtext0,   // H6
    ]

    func makeBody(configuration: Configuration) -> some View {
        let level = min(max(configuration.headingLevel, 1), 6)
        VStack(alignment: .leading, spacing: 3) {
            configuration.label
                .textual.fontScale(Self.scales[level - 1])
                .fontWeight(level <= 2 ? .bold : .semibold)
                .foregroundStyle(Self.colors[level - 1])
            if level <= 2 { Divider().overlay(AppTheme.border) }
        }
    }
}

extension View {
    // Apply the coloured minutes heading style innermost (so it overrides a bundled style's heading).
    @ViewBuilder
    func minutesHeadingStyle(_ enabled: Bool) -> some View {
        if enabled { self.textual.headingStyle(MinutesHeadingStyle()) } else { self }
    }
}
