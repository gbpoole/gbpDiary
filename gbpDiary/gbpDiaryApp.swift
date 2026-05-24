import SwiftUI
import SwiftData

@main
struct gbpDiaryApp: App {
    var sharedModelContainer: ModelContainer = {
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
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .commands {
            AppCommands()
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
