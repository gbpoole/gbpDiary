import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct DocumentSortKeysTests {
    @Test func summaryKey_isLowercasedOrEmpty() {
        let d = Document()
        #expect(d.summaryKey == "")   // nil summary
        d.summary = "Budget Plan"
        #expect(d.summaryKey == "budget plan")
    }

    @Test func descriptionKey_isLowercasedOrEmpty() {
        let d = Document()
        #expect(d.descriptionKey == "")   // nil description
        d.documentDescription = "Q3 Notes"
        #expect(d.descriptionKey == "q3 notes")
    }

    @Test func projectsKey_isSortedLowercasedJoin() {
        let d = Document()
        #expect(d.projectsKey == "")   // no projects
        d.projects = [Project(name: "Zeta"), Project(name: "Alpha")]
        #expect(d.projectsKey == "alpha, zeta")   // sorted then lowercased
    }

    @Test func attachmentCount_countsAttachments() {
        let d = Document()
        #expect(d.attachmentCount == 0)
        d.attachments = [
            Attachment(fileName: "a.pdf", fileURL: URL(fileURLWithPath: "/tmp/a.pdf"), kind: .pdf),
            Attachment(fileName: "b.png", fileURL: URL(fileURLWithPath: "/tmp/b.png"), kind: .image),
        ]
        #expect(d.attachmentCount == 2)
    }
}
