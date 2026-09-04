import Foundation
import Testing
@testable import gbpDiary

struct MarkdownEditorSyncTests {
    @Test func inSync_returnsFalse_andClearsEchoes() {
        var echoes = ["a", "b"]
        #expect(!MarkdownEditorSync.shouldRebuild(incoming: "b", buffer: "b", pendingEchoes: &echoes))
        #expect(echoes.isEmpty)
    }

    @Test func staleSelfEcho_returnsFalse_andConsumesUpToIt() {
        var echoes = ["a", "b", "c"]
        // Buffer already at "c"; a lagging echo "a" arrives — ignore it and drop through "a".
        #expect(!MarkdownEditorSync.shouldRebuild(incoming: "a", buffer: "c", pendingEchoes: &echoes))
        #expect(echoes == ["b", "c"])
    }

    @Test func genuineExternalChange_returnsTrue_andClearsEchoes() {
        var echoes = ["a", "b"]
        // "x" was never something we typed and differs from the buffer → real external change.
        #expect(MarkdownEditorSync.shouldRebuild(incoming: "x", buffer: "b", pendingEchoes: &echoes))
        #expect(echoes.isEmpty)
    }

    // The reported scramble: fast typing A then B leaves buffer="B" with both echoes still queued; neither
    // lagging echo may rebuild (which would revert the buffer and jump the caret).
    @Test func abaScrambleScenario_neverRebuildsForOwnEchoes() {
        var echoes = ["A", "B"]
        let buffer = "B"
        #expect(!MarkdownEditorSync.shouldRebuild(incoming: "A", buffer: buffer, pendingEchoes: &echoes))
        #expect(!MarkdownEditorSync.shouldRebuild(incoming: "B", buffer: buffer, pendingEchoes: &echoes))
    }
}
