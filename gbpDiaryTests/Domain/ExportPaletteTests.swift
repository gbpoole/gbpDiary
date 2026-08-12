import Foundation
import Testing
@testable import gbpDiary

@MainActor
struct ExportPaletteTests {
    @Test func cases_haveDistinctBackgroundsAndSixHeadings() {
        for palette in ExportPalette.allCases {
            #expect(palette.headingColors.count == 6)
        }
        // Light and dark differ in page background.
        #expect(ExportPalette.lightShaded.pageBackground != ExportPalette.dark.pageBackground)
        // Shaded has a distinct card vs page; plain does not.
        #expect(ExportPalette.lightShaded.cardBackground != ExportPalette.lightShaded.pageBackground)
        #expect(ExportPalette.lightPlain.cardBackground == ExportPalette.lightPlain.pageBackground)
        #expect(ExportPalette.lightShaded.isLight)
        #expect(!ExportPalette.dark.isLight)
    }

    @Test func css_formatsSixDigitHex() {
        #expect(ExportPalette.css(0x1F1F28) == "#1F1F28")
        #expect(ExportPalette.css(0xFFFFFF) == "#FFFFFF")
    }

    @Test func bodyHTMLDocument_embedsHeadingColour() {
        let html = ExportPalette.lightShaded.bodyHTMLDocument("# Title")
        #expect(html.contains("<h1"))
        #expect(html.contains(ExportPalette.css(ExportPalette.lightShaded.headingColors[0])))
        #expect(html.contains("<html>"))
    }

    @Test func store_pagePalette_defaultsAndRoundTrips() {
        UserDefaults.standard.removeObject(forKey: "pagePalette")
        #expect(AppSettingsStore.pagePalette == .lightShaded)   // default
        AppSettingsStore.pagePalette = .dark
        #expect(AppSettingsStore.pagePalette == .dark)
        UserDefaults.standard.removeObject(forKey: "pagePalette")
    }
}
