import SwiftUI
import SwiftData

@main
struct gbpDiaryApp: App {
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
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { sweepOrphanedAttachments() }
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
            known = Set(try context.fetch(FetchDescriptor<Attachment>()).map(\.fileURL))
        } catch { return }
        let dir = AttachmentStorage.attachmentsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }
        for file in files where !known.contains(file) {
            try? FileManager.default.removeItem(at: file)
        }
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
