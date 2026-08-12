import SwiftUI

// The colour theme used when exporting minutes/notes to PDF. Selectable in Settings ▸ Appearance
// (the on-screen theme stays the app's dark Kanagawa for now). Light palettes use light-legible
// variants of the Kanagawa hues (same H1 sapphire … H6 order as `MinutesHeadingStyle`, darkened for
// contrast on a light page); the dark palette uses the on-screen values.
enum ExportPalette: String, CaseIterable, Identifiable {
    case lightShaded
    case lightPlain
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lightShaded: "Light (shaded)"
        case .lightPlain:  "Light (plain)"
        case .dark:        "Dark"
        }
    }

    // MARK: - Colour values (hex)

    /// The outer page colour.
    var pageBackground: UInt {
        switch self {
        case .lightShaded: 0xFFFFFF
        case .lightPlain:  0xFFFFFF
        case .dark:        0x1F1F28   // Kanagawa base
        }
    }

    /// The content card colour (shaded on `lightShaded`, else same as the page).
    var cardBackground: UInt {
        switch self {
        case .lightShaded: 0xE9EBF2   // soft lavender-grey card
        case .lightPlain:  0xFFFFFF
        case .dark:        0x2A2A37   // Kanagawa surface0
        }
    }

    var bodyText: UInt {
        switch self {
        case .lightShaded, .lightPlain: 0x1F1F28   // dark
        case .dark:                     0xDCD7BA   // Kanagawa text
        }
    }

    var mutedText: UInt {
        switch self {
        case .lightShaded, .lightPlain: 0x5A5A66
        case .dark:                     0xC8C093   // Kanagawa subtext0
        }
    }

    /// Heading colours H1…H6 (same hue order as `MinutesHeadingStyle`).
    var headingColors: [UInt] {
        switch self {
        case .lightShaded, .lightPlain:
            // Darkened, contrast-safe variants of sapphire/teal/green/mauve/peach/gold.
            [0x2E6E96, 0x2F7266, 0x5A8438, 0x66509A, 0xC96A2C, 0x7A6A2E]
        case .dark:
            [0x7FB4CA, 0x7AA89F, 0x98BB6C, 0x957FB8, 0xFFA066, 0xC8C093]
        }
    }

    /// The accent used for the title and section headers (H1 colour).
    var accent: UInt { headingColors[0] }

    // MARK: - SwiftUI accessors

    var pageColor: Color { Color(hex: pageBackground) }
    var cardColor: Color { Color(hex: cardBackground) }
    var bodyTextColor: Color { Color(hex: bodyText) }
    var mutedTextColor: Color { Color(hex: mutedText) }
    var accentColor: Color { Color(hex: accent) }
    func headingColor(_ level: Int) -> Color { Color(hex: headingColors[clampLevel(level)]) }

    /// `true` when the page is light (used to force `.light` colour scheme when rendering).
    var isLight: Bool { self != .dark }

    // MARK: - CSS

    static func css(_ hex: UInt) -> String { String(format: "#%06X", hex & 0xFF_FFFF) }

    /// A full HTML document for the given note markdown, styled with this palette. Images are handled
    /// separately (as `NSImageView`s) so the resolver returns nil here.
    func bodyHTMLDocument(_ markdown: String) -> String {
        let body = MarkdownHTML.render(markdown) { _ in nil }
        let h = headingColors.map { ExportPalette.css($0) }
        let css = """
        <style>
        body{font-family:-apple-system,Helvetica,sans-serif;font-size:13px;color:\(ExportPalette.css(bodyText));line-height:1.5;margin:0;padding:0}
        h1{color:\(h[0]);font-size:20px;font-weight:700;margin:14px 0 6px}
        h2{color:\(h[1]);font-size:17px;font-weight:700;margin:12px 0 5px}
        h3{color:\(h[2]);font-size:14px;font-weight:700;margin:10px 0 4px}
        h4{color:\(h[3]);font-size:13px;font-weight:700;margin:8px 0 3px}
        h5{color:\(h[4]);font-size:13px;font-weight:700;margin:8px 0 3px}
        h6{color:\(h[5]);font-size:13px;font-weight:700;margin:8px 0 3px}
        p{margin:0 0 8px}
        ul,ol{margin:0 0 8px;padding-left:22px}
        li{margin-bottom:2px}
        table{border-collapse:collapse;margin:8px 0;width:100%}
        th,td{border:1px solid \(ExportPalette.css(mutedText))55;padding:4px 8px;text-align:left;font-size:12px}
        th{font-weight:700}
        pre{background-color:\(isLight ? "#F2F2F5" : "#00000033");padding:8px;border-radius:3px;margin:8px 0;white-space:pre-wrap}
        code{font-family:ui-monospace,monospace;font-size:11px;background-color:\(isLight ? "#F2F2F5" : "#00000033");padding:1px 4px;border-radius:2px}
        pre code{background:none;padding:0}
        blockquote{border-left:3px solid \(ExportPalette.css(mutedText));margin:4px 0 8px 0;padding:0 12px;color:\(ExportPalette.css(mutedText))}
        hr{border:none;border-top:1px solid \(ExportPalette.css(mutedText))55;margin:12px 0}
        </style>
        """
        return "<html><head><meta charset='utf-8'>\(css)</head><body>\(body)</body></html>"
    }

    private func clampLevel(_ level: Int) -> Int { min(max(level, 1), 6) - 1 }
}
