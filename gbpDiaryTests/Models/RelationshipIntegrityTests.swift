import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct RelationshipIntegrityTests {
    @Test func dayRecordDelete_cascadesEntries() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let record = DayRecord(date: FixedDates.reference)
        let entry = DayEntry(kind: .note, text: "n")
        entry.dayRecord = record
        context.insert(record)
        context.insert(entry)
        try context.save()

        context.delete(record)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<DayEntry>())
        #expect(remaining.isEmpty)
    }

    @Test func documentDelete_cascadesAttachments() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let document = Document(summary: "doc")
        let attachment = gbpDiary.Attachment(
            fileName: "a.pdf",
            fileURL: URL(fileURLWithPath: "/tmp/a.pdf"),
            kind: .pdf
        )
        attachment.document = document
        context.insert(document)
        context.insert(attachment)
        try context.save()

        context.delete(document)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<gbpDiary.Attachment>())
        #expect(remaining.isEmpty)
    }

    @Test func projectPersonInverseRelationship_isMaintained() {
        let project = Project(name: "P")
        let person = Person(name: "A")
        project.devTeam = [person]

        #expect(project.devTeam.first?.id == person.id)
        #expect(person.devProjects.first?.id == project.id)
    }
}
