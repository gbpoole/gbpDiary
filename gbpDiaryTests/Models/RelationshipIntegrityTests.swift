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

    @Test func institutionDelete_nullifiesMemberInstitution() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let inst = Institution(name: "Acme")
        let person = Person(name: "A")
        person.institution = inst
        context.insert(inst)
        context.insert(person)
        try context.save()

        context.delete(inst)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Institution>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Person>()).first?.institution == nil)
    }

    @Test func projectDelete_nullifiesReferences() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let project = Project(name: "P")
        let task = Task(summary: "t")
        task.project = project
        let minutes = Minutes(meetingAt: FixedDates.reference)
        minutes.projects = [project]
        context.insert(project)
        context.insert(task)
        context.insert(minutes)
        try context.save()

        context.delete(project)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<Project>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Task>()).first?.project == nil)
        #expect(try context.fetch(FetchDescriptor<Minutes>()).first?.projects.isEmpty == true)
    }

    @Test func personDelete_nullifiesReferences() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let person = Person(name: "A")
        let minutes = Minutes(meetingAt: FixedDates.reference)
        minutes.attendees = [person]
        let task = Task(summary: "t")
        task.assignee = person
        context.insert(person)
        context.insert(minutes)
        context.insert(task)
        try context.save()

        context.delete(person)
        try context.save()

        // The Person is gone; the meeting/task survive with the reference nullified.
        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty)
        let remainingMinutes = try context.fetch(FetchDescriptor<Minutes>())
        #expect(remainingMinutes.first?.attendees.isEmpty == true)
        let remainingTasks = try context.fetch(FetchDescriptor<Task>())
        #expect(remainingTasks.first?.assignee == nil)
    }
}
