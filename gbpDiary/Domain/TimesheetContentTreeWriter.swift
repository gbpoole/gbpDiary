import Foundation

// The only filesystem code in the content export. Deliberately trivial: `TimesheetContentTree` decides the
// entire layout as data, so this just puts it on disk.
//
// Writes into a staging directory first and swaps it in, so a re-export replaces the tree wholesale rather
// than leaving last run's files mixed in with this one's.
enum TimesheetContentTreeWriter {
    static func write(_ files: [TimesheetExportFile], to destination: URL) throws {
        let manager = FileManager.default
        let staging = manager.temporaryDirectory
            .appendingPathComponent("gbpDiary-export-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }

        for file in files {
            let url = staging.appendingPathComponent(file.path)
            try manager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
        }

        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try manager.createDirectory(at: destination.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
            try manager.moveItem(at: staging, to: destination)
        }
    }
}
