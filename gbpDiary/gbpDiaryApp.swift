import SwiftUI
import SwiftData
import Darwin

#if os(macOS)
import AppKit
#endif

@main
struct gbpDiaryApp: App {
    @State private var didRunBundleImport = false
    @State private var minutesEditorContext = MinutesEditorContext()

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
            ContentView()
                .environment(minutesEditorContext)
                .onAppear {
                    sweepOrphanedAttachments()
                    runBundleImportIfRequested()
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            AppCommands()
        }
    }

    private func sweepOrphanedAttachments() {
        let context = sharedModelContainer.mainContext
        let known: Set<URL>
        do {
            let attachments = try context.fetch(FetchDescriptor<Attachment>())
            var urls = Set(attachments.map(\.fileURL))
            for att in attachments { if let r = att.renderURL { urls.insert(r) } }
            known = urls
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
    var body: some Commands {
        CommandMenu("Task") {
            Button("New Task") {}
                .keyboardShortcut("n", modifiers: .command)
        }
    }
}
