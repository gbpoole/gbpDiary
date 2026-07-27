import Foundation
import SwiftData
import Testing
@testable import gbpDiary

@MainActor
struct ObsidianBundleImporterTests {
    @Test func launchRequest_parsesBundlePathAndExitFlag() {
        let request = ObsidianImportLaunchRequest(arguments: [
            "gbpDiary",
            "-ui-testing",
            "--import-obsidian-bundle",
            "/tmp/bundle.json",
            "--exit-after-import",
        ])

        #expect(request?.bundlePath == "/tmp/bundle.json")
        #expect(request?.exitAfterImport == true)
    }

    @Test func launchRequest_requiresBundlePath() {
        #expect(ObsidianImportLaunchRequest(arguments: ["gbpDiary"]) == nil)
        #expect(ObsidianImportLaunchRequest(arguments: ["gbpDiary", "--import-obsidian-bundle"]) == nil)
    }

    @Test func importBundle_createsRelationshipsAndTaskMetadata() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let data = Data(fixtureJSON.utf8)
        let bundle = try JSONDecoder().decode(ObsidianImportBundle.self, from: data)

        let report = try ObsidianBundleImporter(context: context).importBundle(bundle)

        #expect(report.institutions == 1)
        #expect(report.people == 1)
        #expect(report.projects == 1)
        #expect(report.minutes == 1)
        #expect(report.notes == 1)
        #expect(report.dayRecords == 1)
        #expect(report.tasks == 1)

        let people = try context.fetch(FetchDescriptor<Person>())
        let projects = try context.fetch(FetchDescriptor<Project>())
        let minutes = try context.fetch(FetchDescriptor<Minutes>())
        let dayRecords = try context.fetch(FetchDescriptor<DayRecord>())
        let tasks = try context.fetch(FetchDescriptor<Task>())

        #expect(people.first?.institution?.name == "Test Institute")
        #expect(projects.first?.devTeam.first?.name == "Ada Lovelace")
        #expect(minutes.first?.note?.content == "Meeting notes")
        #expect(dayRecords.count == 1)
        #expect(dayRecords.first?.entries.first?.minutes?.summary == "Planning")
        #expect(tasks.first?.assignee?.name == "Ada Lovelace")
        #expect(tasks.first?.project?.name == "Test Project")
        #expect(tasks.first?.originMinutes?.summary == "Planning")
        #expect(tasks.first?.status == .completed)
        #expect(tasks.first?.duration?.hoursNormalized == 1.5)
        #expect(tasks.first?.tags == ["timesheet"])
        #expect(tasks.first?.notes == nil)
    }

    @Test func importBundle_createsContentNoteWithTitleAndProject() throws {
        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let projectId = "00000000-0000-5000-8000-0000000000A1"
        let noteId = "00000000-0000-5000-8000-0000000000A2"
        let json = """
        {
          "schemaVersion": 1,
          "counts": {},
          "institutions": [],
          "people": [],
          "projects": [{"id": "\(projectId)", "name": "Foo"}],
          "minutes": [],
          "documents": [],
          "notes": [{"id": "\(noteId)", "title": "Idea about Foo", "content": "Some idea text", "tags": ["idea"], "projectId": "\(projectId)", "sourcePath": "Notes/Idea about Foo.md"}],
          "dayRecords": [],
          "tasks": [],
          "diagnostics": []
        }
        """
        let bundle = try JSONDecoder().decode(ObsidianImportBundle.self, from: Data(json.utf8))
        let report = try ObsidianBundleImporter(context: context).importBundle(bundle)

        #expect(report.notes == 1)
        let notes = try context.fetch(FetchDescriptor<Note>())
        let note = try #require(notes.first)
        #expect(note.title == "Idea about Foo")
        #expect(note.project?.name == "Foo")
        #expect(note.dayRecord == nil)
        #expect(note.isContentNote == true)
    }

    @Test func importBundle_createsFocusBlocksAndCopiesDocumentAttachments() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("obsidian-importer-test-\(UUID().uuidString)")
        let vault = tempDir.appendingPathComponent("Vault")
        let attachmentDir = vault.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: attachmentDir, withIntermediateDirectories: true)
        let sourceFile = attachmentDir.appendingPathComponent("paper.pdf")
        try Data("pdf".utf8).write(to: sourceFile)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let json = focusBlockAndAttachmentFixture(vaultPath: vault.path)
        let bundle = try JSONDecoder().decode(ObsidianImportBundle.self, from: Data(json.utf8))

        let report = try ObsidianBundleImporter(context: context).importBundle(bundle)

        #expect(report.focusBlocks == 1)
        #expect(report.dayRecords == 1)
        #expect(report.attachments == 1)

        let focusBlocks = try context.fetch(FetchDescriptor<FocusBlock>())
        let documents = try context.fetch(FetchDescriptor<Document>())
        let attachments = try context.fetch(FetchDescriptor<gbpDiary.Attachment>())

        #expect(focusBlocks.first?.displayLabel == "Apply for access")
        #expect(focusBlocks.first?.duration.hoursNormalized == 1.5)
        #expect(focusBlocks.first?.task?.project?.name == "YWang_2026A")
        #expect(focusBlocks.first?.task?.assignee?.name == "Owen Cole")
        #expect(documents.first?.attachments.count == 1)
        #expect(attachments.first?.fileName == "paper.pdf")
        #expect(attachments.first?.kind == .pdf)
        #expect(FileManager.default.fileExists(atPath: attachments.first?.fileURL.path ?? "") == true)
    }

    @Test func importBundle_copiesNoteImageAttachmentsAndImportsTags() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("obsidian-note-image-importer-test-\(UUID().uuidString)")
        let vault = tempDir.appendingPathComponent("Vault")
        let imageDir = vault.appendingPathComponent("Diary/Note")
        try FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)
        let sourceFile = imageDir.appendingPathComponent("plot.png")
        try Data("png".utf8).write(to: sourceFile)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let container = try TestModelContainer.make()
        let context = ModelContext(container)
        let dayRecordId = UUID()
        let noteId = UUID()
        let attachmentId = UUID()
        let json = noteImageFixture(vaultPath: vault.path, dayRecordId: dayRecordId, noteId: noteId, attachmentId: attachmentId)
        let bundle = try JSONDecoder().decode(ObsidianImportBundle.self, from: Data(json.utf8))

        let report = try ObsidianBundleImporter(context: context).importBundle(bundle)

        #expect(report.notes == 1)
        #expect(report.dayRecords == 1)
        #expect(report.attachments == 1)

        let notes = try context.fetch(FetchDescriptor<Note>())
        let dayRecords = try context.fetch(FetchDescriptor<DayRecord>())
        let attachments = try context.fetch(FetchDescriptor<gbpDiary.Attachment>())

        #expect(notes.first?.tags == ["milestone", "weekly"])
        #expect(notes.first?.content.contains("#milestone") == true)
        // Legacy block arrays flatten into markdown with an inline managed image ref.
        let noteContent = notes.first?.content ?? ""
        #expect(noteContent.contains("After"))
        if let attId = attachments.first?.id {
            #expect(noteContent.contains(AttachmentRef.url(for: attId)))
            #expect(AttachmentRef.referencedIDs(in: noteContent) == [attId])
        }
        #expect(notes.first?.attachments.first?.kind == .image)
        #expect(dayRecords.first?.focusTags == ["diary-tag"])
        #expect(FileManager.default.fileExists(atPath: attachments.first?.fileURL.path ?? "") == true)
    }

    private var fixtureJSON: String {
        """
        {
          "schemaVersion": 1,
          "generatedAt": "2026-06-12T00:00:00",
          "vaultPath": "/tmp/vault",
          "counts": {},
          "summary": {},
          "diagnostics": [],
          "institutions": [
            {"id": "00000000-0000-5000-8000-000000000001", "name": "Test Institute"}
          ],
          "people": [
            {"id": "00000000-0000-5000-8000-000000000002", "name": "Ada Lovelace", "email": "ada@example.com", "institutionId": "00000000-0000-5000-8000-000000000001", "tags": []}
          ],
          "projects": [
            {"id": "00000000-0000-5000-8000-000000000003", "name": "Test Project", "description": "Project description", "stream": "Research", "isCompleted": false, "devTeamPersonIds": ["00000000-0000-5000-8000-000000000002"], "sciTeamPersonIds": [], "institutionIds": ["00000000-0000-5000-8000-000000000001"], "tags": []}
          ],
          "notes": [
            {"id": "00000000-0000-5000-8000-000000000004", "content": "Meeting notes", "blocks": [{"kind": "text", "textContent": "Meeting notes"}]}
          ],
          "minutes": [
            {"id": "00000000-0000-5000-8000-000000000005", "summary": "Planning", "meetingAt": "2026-06-12T09:30", "duration": {"value": 1, "unit": "h", "hoursNormalized": 1}, "projectIds": ["00000000-0000-5000-8000-000000000003"], "attendeePersonIds": ["00000000-0000-5000-8000-000000000002"], "noteId": "00000000-0000-5000-8000-000000000004"}
          ],
          "documents": [],
          "dayRecords": [],
          "tasks": [
            {"id": "00000000-0000-5000-8000-000000000006", "summary": "Do work", "rawText": "Do work (duration:: 1.5 h) #timesheet", "notes": "", "status": "completed", "tags": ["timesheet"], "duration": {"value": 1.5, "unit": "h", "hoursNormalized": 1.5}, "completedAt": "2026-06-12", "indent": 0, "line": 10, "sourcePath": "CMS/Minutes/Test.md", "projectId": "00000000-0000-5000-8000-000000000003", "assigneePersonId": "00000000-0000-5000-8000-000000000002", "originMinutesId": "00000000-0000-5000-8000-000000000005"}
          ]
        }
        """
    }

    private func focusBlockAndAttachmentFixture(vaultPath: String) -> String {
        """
        {
          "schemaVersion": 1,
          "generatedAt": "2026-06-12T00:00:00",
          "vaultPath": "\(vaultPath)",
          "counts": {},
          "summary": {},
          "diagnostics": [],
          "institutions": [],
          "people": [
            {"id": "00000000-0000-5000-8000-000000000011", "name": "Owen Cole"}
          ],
          "projects": [
            {"id": "00000000-0000-5000-8000-000000000012", "name": "YWang_2026A", "tags": []}
          ],
          "notes": [],
          "minutes": [],
          "documents": [
            {"id": "00000000-0000-5000-8000-000000000013", "summary": "Paper", "attachmentRefs": ["Files/paper.pdf"], "sourceContext": {"sourceRecordId": "CMS/Documents/Paper.md"}}
          ],
          "dayRecords": [
            {"id": "00000000-0000-5000-8000-000000000014", "date": "2026-03-02"}
          ],
          "focusBlocks": [
            {"id": "00000000-0000-5000-8000-000000000015", "summary": "Apply for access", "duration": {"value": 1.5, "unit": "h", "hoursNormalized": 1.5}, "slot": "allDay", "sortOrder": 10, "taskId": "00000000-0000-5000-8000-000000000016", "projectId": "00000000-0000-5000-8000-000000000012", "assigneePersonId": "00000000-0000-5000-8000-000000000011", "dayRecordId": "00000000-0000-5000-8000-000000000014"}
          ],
          "tasks": []
        }
        """
    }

    private func noteImageFixture(vaultPath: String, dayRecordId: UUID, noteId: UUID, attachmentId: UUID) -> String {
        """
        {
          "schemaVersion": 1,
          "generatedAt": "2026-06-12T00:00:00",
          "vaultPath": "\(vaultPath)",
          "counts": {},
          "summary": {},
          "diagnostics": [],
          "institutions": [],
          "people": [],
          "projects": [],
          "minutes": [],
          "documents": [],
          "dayRecords": [
            {"id": "\(dayRecordId.uuidString)", "date": "2026-03-02", "tags": ["diary-tag"]}
          ],
          "notes": [
            {"id": "\(noteId.uuidString)", "content": "Before #milestone\\n\\n![[plot.png]]\\n\\nAfter", "tags": ["milestone", "weekly"], "dayRecordId": "\(dayRecordId.uuidString)", "sourcePath": "Diary/Note.md", "sourceContext": {"sourceRecordId": "Diary/Note.md"}, "attachments": [{"id": "\(attachmentId.uuidString)", "ref": "Diary/Note/plot.png", "fileName": "plot.png", "kind": "image"}], "blocks": [{"kind": "text", "textContent": "Before #milestone"}, {"kind": "image", "attachmentId": "\(attachmentId.uuidString)"}, {"kind": "text", "textContent": "After"}]}
          ],
          "tasks": []
        }
        """
    }
}
