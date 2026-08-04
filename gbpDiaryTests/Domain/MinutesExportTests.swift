import Testing
import Foundation
@testable import gbpDiary

@Suite("MinutesExport")
struct MinutesExportTests {
    @Test func rewriteImageLinks_replacesRefsWithRelativePaths() {
        let id = UUID()
        let md = "text\n\n![pic](attachment://\(id.uuidString))\n\nmore"
        let out = MinutesExport.rewriteImageLinks(md) { $0 == id ? "images/\($0.uuidString).png" : nil }
        #expect(out == "text\n\n![pic](images/\(id.uuidString).png)\n\nmore")
    }

    @Test func rewriteImageLinks_leavesUnmappedRefsUntouched() {
        let id = UUID()
        let md = "![p](attachment://\(id.uuidString))"
        let out = MinutesExport.rewriteImageLinks(md) { _ in nil }
        #expect(out == md)
    }

    @Test func bundleFileName_usesUUIDWithExtension() {
        let id = UUID()
        #expect(MinutesExport.bundleFileName(id: id, originalFileName: "photo.PNG") == "\(id.uuidString).PNG")
        #expect(MinutesExport.bundleFileName(id: id, originalFileName: "noext") == id.uuidString)
    }

    @Test func exportBaseName_sanitisesAndFallsBack() {
        #expect(MinutesExport.exportBaseName(summary: "Team sync: Q3/Q4") == "Team sync Q3Q4")
        #expect(MinutesExport.exportBaseName(summary: "   ") == "Minutes")
        #expect(MinutesExport.exportBaseName(summary: nil) == "Minutes")
    }

    @Test func initials_takesFirstLetterOfEachWord() {
        #expect(MinutesExport.initials("Ada Lovelace") == "AL")
        #expect(MinutesExport.initials("madonna") == "M")
        #expect(MinutesExport.initials("Jean Luc Picard") == "JLP")
        #expect(MinutesExport.initials("  ") == "")
    }

    @Test func composeMarkdown_buildsHeaderActionsDocumentsBody() {
        let out = MinutesExport.composeMarkdown(
            title: "Sync", dateLine: "Wed 30 Jul 2026, 9:00 AM",
            metaLines: ["**Projects:** NODES", "**Attendees:** Ada Lovelace"],
            actionItems: ["AL: ship it — Ada Lovelace"], documents: ["Spec (1 file)"],
            body: "Notes here.")
        #expect(out == """
        # Sync
        Wed 30 Jul 2026, 9:00 AM
        **Projects:** NODES
        **Attendees:** Ada Lovelace

        ---

        ## Action Items
        - AL: ship it — Ada Lovelace

        ## Documents
        - Spec (1 file)

        ---

        Notes here.

        """)
    }

    @Test func composeMarkdown_noneActions_andOmitsEmptyDocuments() {
        let out = MinutesExport.composeMarkdown(
            title: "", dateLine: "", metaLines: [], actionItems: [], documents: [], body: "")
        #expect(out == "# Meeting\n\n---\n\n## Action Items\n_None._\n")
    }
}
