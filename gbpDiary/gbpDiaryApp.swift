import SwiftUI
import SwiftData
import Darwin

#if os(macOS)
import AppKit
#endif

@main
struct gbpDiaryApp: App {
    @State private var didRunBundleImport = false
    @State private var workspace = WorkspaceModel()
    @State private var hotkeys = HotkeySettings()
    @AppStorage(SettingsTab.storageKey) private var settingsTab = SettingsTab.general

    var sharedModelContainer: ModelContainer = {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let schema = Schema([
            Task.self,
            DayRecord.self,
            DayEntry.self,
            Project.self,
            Person.self,
            Institution.self,
            Minutes.self,
            Attachment.self,
            Document.self,
            Note.self,
            TaskTimeEntry.self,
            FocusBlock.self,
            EmailMessage.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        guard let request = ObsidianImportLaunchRequest(arguments: ProcessInfo.processInfo.arguments),
              request.exitAfterImport else { return }
        let succeeded = Self.runBundleImport(request, in: sharedModelContainer)
        exit(succeeded ? 0 : 1)
    }

    var body: some Scene {
        WindowGroup {
            WorkspaceView()
                .environment(workspace)
                .environment(hotkeys)
                .onAppear {
                    sweepOrphanedAttachments()
                    runBundleImportIfRequested()
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            AppCommands(workspace: workspace, hotkeys: hotkeys)
        }
        #if os(macOS)
        Settings {
            TabView(selection: $settingsTab) {
                GeneralSettingsView()
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(SettingsTab.general)
                CalendarSettingsView()
                    .tabItem { Label("Calendar", systemImage: "calendar") }
                    .tag(SettingsTab.calendar)
                EmailSettingsView()
                    .tabItem { Label("Email", systemImage: "envelope") }
                    .tag(SettingsTab.email)
                HotkeySettingsView()
                    .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                    .tag(SettingsTab.shortcuts)
                AppearanceSettingsView()
                    .tabItem { Label("Appearance", systemImage: "paintpalette") }
                    .tag(SettingsTab.appearance)
            }
            .environment(hotkeys)
            .modelContainer(sharedModelContainer)
        }
        #endif
    }

    private func sweepOrphanedAttachments() {
        let context = sharedModelContainer.mainContext
        let known: Set<URL>
        do {
            let attachments = try context.fetch(FetchDescriptor<Attachment>())
            known = Set(attachments.map(\.fileURL))
        } catch { return }
        let dir = AttachmentStorage.attachmentsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }
        for file in files where !known.contains(file) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func runBundleImportIfRequested() {
        guard !didRunBundleImport else { return }
        didRunBundleImport = true
        let args = ProcessInfo.processInfo.arguments
        guard let request = ObsidianImportLaunchRequest(arguments: args) else { return }
        _ = Self.runBundleImport(request, in: sharedModelContainer)
        if request.exitAfterImport {
            #if os(macOS)
            NSApp.terminate(nil)
            #endif
        }
    }

    private static func runBundleImport(_ request: ObsidianImportLaunchRequest, in container: ModelContainer) -> Bool {
        let url = URL(fileURLWithPath: request.bundlePath)
        do {
            let report = try ObsidianBundleImporter(context: container.mainContext)
                .importBundle(from: url)
            print("Obsidian import completed: \(report)")
            fflush(stdout)
            return true
        } catch {
            print("Obsidian import failed: \(error)")
            fflush(stdout)
            return false
        }
    }
}

struct ObsidianImportLaunchRequest: Equatable {
    var bundlePath: String
    var exitAfterImport: Bool

    init?(arguments: [String]) {
        guard let flagIndex = arguments.firstIndex(of: "--import-obsidian-bundle"),
              arguments.indices.contains(flagIndex + 1) else { return nil }
        bundlePath = arguments[flagIndex + 1]
        exitAfterImport = arguments.contains("--exit-after-import")
    }
}

struct AppCommands: Commands {
    /// The shared workspace whose tabs the shortcuts drive. Same instance as the WindowGroup's.
    let workspace: WorkspaceModel
    /// User-configurable hotkey bindings (Settings ▸ Shortcuts). Read here so menu shortcuts update live.
    let hotkeys: HotkeySettings

    var body: some Commands {
        CommandMenu("Tabs") {
            Button("New Tab") { workspace.newTab() }
                .keyboardShortcut(hotkeys.hotkey(for: .newTab).keyboardShortcut)
            // Close Tab is handled by CloseTabKeyMonitor (WorkspaceView), not a menu shortcut: a menu
            // shortcut on the default ⌘W would collide with the standard File ▸ Close and lose to it.
            Button("Close Tab") { workspace.closeActiveTab() }
            Divider()
            Button("Show Next Tab") { workspace.selectNextTab() }
                .keyboardShortcut(hotkeys.hotkey(for: .nextTab).keyboardShortcut)
            Button("Show Previous Tab") { workspace.selectPreviousTab() }
                .keyboardShortcut(hotkeys.hotkey(for: .previousTab).keyboardShortcut)
            Divider()
            // ⌘1…⌘8 jump to that tab by position (fixed); ⌘9 = the configurable "Show Last Tab".
            ForEach(1...8, id: \.self) { n in
                Button("Show Tab \(n)") { workspace.selectTab(at: n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
            Button("Show Last Tab") { workspace.selectLastTab() }
                .keyboardShortcut(hotkeys.hotkey(for: .lastTab).keyboardShortcut)
        }
    }
}
