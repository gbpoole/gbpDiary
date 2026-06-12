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
        #expect(report.tasks == 1)

        let people = try context.fetch(FetchDescriptor<Person>())
        let projects = try context.fetch(FetchDescriptor<Project>())
        let minutes = try context.fetch(FetchDescriptor<Minutes>())
        let tasks = try context.fetch(FetchDescriptor<Task>())

        #expect(people.first?.institution?.name == "Test Institute")
        #expect(projects.first?.devTeam.first?.name == "Ada Lovelace")
        #expect(minutes.first?.note?.content == "Meeting notes")
        #expect(tasks.first?.assignee?.name == "Ada Lovelace")
        #expect(tasks.first?.project?.name == "Test Project")
        #expect(tasks.first?.originMinutes?.summary == "Planning")
        #expect(tasks.first?.status == .completed)
        #expect(tasks.first?.duration?.hoursNormalized == 1.5)
        #expect(tasks.first?.tags == ["timesheet"])
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
            {"id": "00000000-0000-5000-8000-000000000006", "summary": "Do work", "rawText": "Do work (duration:: 1.5 h) #timesheet", "status": "completed", "tags": ["timesheet"], "duration": {"value": 1.5, "unit": "h", "hoursNormalized": 1.5}, "completedAt": "2026-06-12", "indent": 0, "line": 10, "sourcePath": "CMS/Minutes/Test.md", "projectId": "00000000-0000-5000-8000-000000000003", "assigneePersonId": "00000000-0000-5000-8000-000000000002", "originMinutesId": "00000000-0000-5000-8000-000000000005"}
          ]
        }
        """
    }
}
