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

    @Test func personDelete_nullifiesEmailPerson() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let person = Person(name: "A")
        let email = EmailMessage(messageId: "<m1>", account: "acct", mailbox: "INBOX",
                                 direction: .inbox, fromAddress: "a@x.com", fromName: "A",
                                 subject: "hi", date: FixedDates.reference)
        email.person = person
        context.insert(person)
        context.insert(email)
        try context.save()

        context.delete(person)
        try context.save()

        // The Person is gone; the email survives with its person nullified.
        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty)
        let remaining = try context.fetch(FetchDescriptor<EmailMessage>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.person == nil)
    }

    @Test func emailDelete_nullifiesTaskOriginEmail_taskSurvives() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let email = EmailMessage(messageId: "<m3>", account: "acct", mailbox: "INBOX",
                                 direction: .inbox, fromAddress: "a@x.com", fromName: "A",
                                 subject: "do this", date: FixedDates.reference)
        let task = Task(summary: "do this")
        task.originEmail = email
        context.insert(email)
        context.insert(task)
        try context.save()

        context.delete(email)
        try context.save()

        // The email is gone; the todo survives with its origin nullified.
        #expect(try context.fetch(FetchDescriptor<EmailMessage>()).isEmpty)
        let remaining = try context.fetch(FetchDescriptor<Task>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.originEmail == nil)
    }

    @Test func projectDelete_removesEmailProjectLink() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)

        let project = Project(name: "P")
        let email = EmailMessage(messageId: "<m2>", account: "acct", mailbox: "INBOX",
                                 direction: .inbox, fromAddress: "a@x.com", fromName: "A",
                                 subject: "hi", date: FixedDates.reference)
        email.projects = [project]
        context.insert(project)
        context.insert(email)
        try context.save()

        context.delete(project)
        try context.save()

        // The Project is gone; the email survives with the link removed.
        #expect(try context.fetch(FetchDescriptor<Project>()).isEmpty)
        let remaining = try context.fetch(FetchDescriptor<EmailMessage>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.projects.isEmpty == true)
    }
}
