import Foundation
import Testing
@testable import gbpDiary

// The only filesystem part of the content export (everything decidable lives in `TimesheetContentTree`),
// so this exercises it in a temp directory — mirroring `MinutesExportRenderTests`' approach.
struct TimesheetContentTreeWriterTests {
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tree-writer-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func createsNestedDirectoriesAndWritesEveryFile() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try TimesheetContentTreeWriter.write([
            .init(path: "README.md", contents: "# Content"),
            .init(path: "NODES/meetings/2026-01-06 Requirements.md", contents: "# Requirements"),
            .init(path: "Unattributed/email/2026-01-06 Building access.md", contents: "# Building access"),
        ], to: root)

        func read(_ path: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        #expect(try read("README.md") == "# Content")
        #expect(try read("NODES/meetings/2026-01-06 Requirements.md") == "# Requirements")
        #expect(try read("Unattributed/email/2026-01-06 Building access.md") == "# Building access")
    }

    // Re-exporting the same period must not leave the previous run's files mixed in with this one's.
    @Test func reExportReplacesTheTreeWholesale() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try TimesheetContentTreeWriter.write([
            .init(path: "NODES/meetings/stale.md", contents: "old"),
        ], to: root)
        try TimesheetContentTreeWriter.write([
            .init(path: "NODES/meetings/fresh.md", contents: "new"),
        ], to: root)

        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("NODES/meetings/fresh.md").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("NODES/meetings/stale.md").path))
    }
}
