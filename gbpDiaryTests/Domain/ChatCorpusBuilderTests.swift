import Foundation
import Testing
@testable import gbpDiary

#if canImport(PDFKit)
import CoreGraphics
import CoreText
#endif

@Suite("Chat corpus builder")
struct ChatCorpusBuilderTests {
    @Test func build_projectsAllSupportedModelsAndExcludesDismissedEmail() throws {
        let project = Project(name: "Apollo", id: id(1))
        project.projectDescription = "Lunar research"
        let person = Person(name: "Ada Lovelace", id: id(2))
        person.emails = ["ada@example.com"]
        let institution = Institution(name: "Research Lab", id: id(3))
        person.institution = institution
        project.devTeam = [person]
        project.institutions = [institution]

        let task = Task(summary: "Prepare launch plan", id: id(4))
        task.notes = "Check the telemetry"
        task.project = project
        task.assignee = person

        let day = DayRecord(date: Date(timeIntervalSince1970: 1_700_000_000), id: id(5))
        day.notes = "Legacy diary text"
        let note = Note(content: "Diary observation", title: "Field notes", id: id(6))
        note.dayRecord = day
        note.project = project

        let meeting = Minutes(meetingAt: Date(timeIntervalSince1970: 1_700_000_100), id: id(7))
        meeting.summary = "Launch review"
        meeting.projects = [project]
        meeting.attendees = [person]
        let minutesNote = Note(content: "Agreed launch criteria", id: id(8))
        meeting.note = minutesNote

        let document = Document(id: id(9), summary: "Flight brief")
        document.documentDescription = "Mission details"
        document.projects = [project]

        let attachmentURL = temporaryURL(extension: "md")
        try Data("# Payload\nAttachment knowledge".utf8).write(to: attachmentURL)
        defer { try? FileManager.default.removeItem(at: attachmentURL) }
        let attachment = Attachment(fileName: "payload.md", fileURL: attachmentURL, kind: .text, id: id(10))
        attachment.document = document

        let email = EmailMessage(messageId: "1", account: "local", mailbox: "INBOX", direction: .inbox,
                                 fromAddress: "ada@example.com", fromName: "Ada", subject: "Launch timing",
                                 date: Date(timeIntervalSince1970: 1_700_000_200), id: id(11))
        email.summary = "Ada asks for the revised date."
        email.person = person
        let dismissed = EmailMessage(messageId: "2", account: "local", mailbox: "INBOX", direction: .inbox,
                                     fromAddress: "x@example.com", fromName: nil, subject: "Secret body marker",
                                     date: Date(), id: id(12))
        dismissed.dismissed = true

        let result = ChatCorpusBuilder().build(
            projects: [project], tasks: [task], people: [person], institutions: [institution],
            meetings: [meeting], notes: [note, minutesNote], days: [day], documents: [document],
            emails: [email, dismissed], attachments: [attachment]
        )

        #expect(Set(result.documents.map(\.source.kind)) == Set(ChatSourceKind.allCases))
        #expect(result.documents.first(where: { $0.source.id == meeting.id })?.markdown.contains("Agreed launch criteria") == true)
        #expect(result.documents.first(where: { $0.source.id == email.id })?.markdown.contains("Ada asks for the revised date") == true)
        #expect(result.documents.contains(where: { $0.source.id == dismissed.id && $0.source.kind == .email }) == false)
        let attachmentDocument = result.documents.first { $0.source.id == attachment.id }
        #expect(attachmentDocument?.markdown.contains("Attachment knowledge") == true)
        #expect(attachmentDocument?.source.navigationKind == .document)
        #expect(attachmentDocument?.source.navigationID == document.id)
        #expect(result.attachmentFailures.isEmpty)
    }

    @Test func attachmentExtractor_supportsUTF8TypesAndHasDeterministicFailuresAndCap() throws {
        let yamlURL = temporaryURL(extension: "yaml")
        try Data("key: abcdef".utf8).write(to: yamlURL)
        defer { try? FileManager.default.removeItem(at: yamlURL) }
        let yaml = Attachment(fileName: "data.yaml", fileURL: yamlURL, kind: .other)
        var extractor = ChatAttachmentTextExtractor()
        extractor.maximumCharacters = 7
        #expect(extractor.extract(yaml).text == "key: ab")

        let binaryURL = temporaryURL(extension: "txt")
        try Data([0xff, 0xfe]).write(to: binaryURL)
        defer { try? FileManager.default.removeItem(at: binaryURL) }
        let binary = Attachment(fileName: "bad.txt", fileURL: binaryURL, kind: .text)
        #expect(extractor.extract(binary).failure == .invalidUTF8)

        let missing = Attachment(fileName: "missing.csv", fileURL: temporaryURL(extension: "csv"), kind: .text)
        #expect(extractor.extract(missing).failure == .missingFile)
    }

    #if canImport(PDFKit)
    @Test func attachmentExtractor_extractsBoundedPDFText() throws {
        let url = temporaryURL(extension: "pdf")
        try writePDF(text: "Searchable PDF knowledge", to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let attachment = Attachment(fileName: "searchable.pdf", fileURL: url, kind: .pdf)
        var extractor = ChatAttachmentTextExtractor()
        extractor.maximumCharacters = 14
        #expect(extractor.extract(attachment).text == "Searchable PDF")
    }
    #endif

    @Test func corpusCapsAreStableRegardlessOfInputOrder() {
        var builder = ChatCorpusBuilder()
        builder.limits.maximumSourcesPerKind = 1
        let first = Project(name: "First", id: id(20))
        let second = Project(name: "Second", id: id(21))
        let one = builder.build(projects: [second, first], tasks: [], people: [], institutions: [], meetings: [],
                                notes: [], days: [], documents: [], emails: [], attachments: []).documents
        let two = builder.build(projects: [first, second], tasks: [], people: [], institutions: [], meetings: [],
                                notes: [], days: [], documents: [], emails: [], attachments: []).documents
        #expect(one == two)
        #expect(one.map(\.source.id) == [first.id])
    }

    @Test func crossModelUUIDCollision_preservesBothDocuments() {
        let sharedID = id(31)
        let project = Project(name: "Project", id: sharedID)
        let task = Task(summary: "Task", id: sharedID)
        let result = ChatCorpusBuilder().build(projects: [project], tasks: [task], people: [], institutions: [],
                                               meetings: [], notes: [], days: [], documents: [], emails: [], attachments: [])
        #expect(Set(result.documents.map(\.id)) == Set([
            ChatSourceKey(kind: .project, modelID: sharedID),
            ChatSourceKey(kind: .task, modelID: sharedID)
        ]))
    }

    @Test func unownedAttachment_navigatesToItsLocalFile() throws {
        let url = temporaryURL(extension: "txt")
        try Data("local text".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let attachment = Attachment(fileName: "local.txt", fileURL: url, kind: .text, id: id(30))
        let result = ChatCorpusBuilder().build(projects: [], tasks: [], people: [], institutions: [], meetings: [],
                                               notes: [], days: [], documents: [], emails: [], attachments: [attachment])
        #expect(result.documents.first?.source.navigationKind == .attachment)
        #expect(result.documents.first?.source.navigationURL == url)
    }

    private func id(_ suffix: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, suffix))
    }

    private func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension(pathExtension)
    }

    #if canImport(PDFKit)
    private func writePDF(text: String, to url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else { throw PDFTestError.cannotCreate }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PDFTestError.cannotCreate
        }
        context.beginPDFPage(nil)
        context.textPosition = CGPoint(x: 40, y: 700)
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        )
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
    }
    #endif
}

#if canImport(PDFKit)
private enum PDFTestError: Error { case cannotCreate }
#endif
