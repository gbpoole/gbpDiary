import SwiftUI

// Appearance preferences. Currently the **page (export) palette** used for PDF export. The on-screen
// theme is fixed to the app's Kanagawa (dark) for now — shown as a disabled row to make the split
// explicit and easy to extend later.
struct AppearanceSettingsView: View {
    @State private var pagePalette: ExportPalette = AppSettingsStore.pagePalette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Screen") {
                    HStack {
                        Text("Theme")
                        Spacer()
                        Text("Kanagawa (dark)").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }

                GroupBox("Page (PDF export)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Palette", selection: $pagePalette) {
                            ForEach(ExportPalette.allCases) { palette in
                                Text(palette.label).tag(palette)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Colours used when downloading minutes/notes as PDF. The original images stay full-resolution.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .frame(minWidth: 460, minHeight: 240)
        .onChange(of: pagePalette) { _, new in AppSettingsStore.pagePalette = new }
    }
}
