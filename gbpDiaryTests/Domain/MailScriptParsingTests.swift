import Testing
import Foundation
@testable import gbpDiary

@Suite("MailScriptParsing")
@MainActor
struct MailScriptParsingTests {
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let FS = MailScriptParsing.fieldSep
    private let RS = MailScriptParsing.recordSep

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return utc.date(from: c)!
    }

    // MARK: - script

    @Test func script_containsDayBoundsAccountAndMailboxes() {
        let s = MailScriptParsing.script(forDay: day(2026, 7, 29), accountName: "Exchange",
                                         inboxMailbox: "Inbox", sentMailbox: "Sent Items", calendar: utc)
        #expect(s.contains("mkDate(2026, 7, 29)"))
        #expect(s.contains("mkDate(2026, 7, 30)"))   // next day (exclusive upper bound)
        #expect(s.contains("account \"Exchange\""))
        #expect(s.contains("mailbox \"Inbox\""))
        #expect(s.contains("mailbox \"Sent Items\""))
    }

    @Test func mailboxesScript_embedsEscapedAccountName() {
        let s = MailScriptParsing.mailboxesScript(accountName: "My \"Work\" Acct")
        #expect(s.contains("account \"My \\\"Work\\\" Acct\""))
        #expect(s.contains("name of every mailbox"))
    }

    @Test func parseNameList_splitsAndTrims() {
        #expect(MailScriptParsing.parseNameList("Inbox\nSent Items\n\n  Drafts  ") == ["Inbox", "Sent Items", "Drafts"])
        #expect(MailScriptParsing.parseNameList("").isEmpty)
    }

    // MARK: - parseOutput

    private func record(_ fields: [String]) -> String { fields.joined(separator: FS) }

    @Test func parseOutput_parsesInboxAndSentRecords() {
        let inbox = record(["in", "<a@x>", "Alice Smith <alice@x.com>", "Hello",
                            "2026", "7", "29", "9", "15", "0"])
        let sent = record(["sent", "<b@x>", "bob@y.com", "Re: Hello",
                           "2026", "7", "29", "14", "0", "30"])
        let drafts = MailScriptParsing.parseOutput(inbox + RS + sent + RS, calendar: utc)
        #expect(drafts.count == 2)
        #expect(drafts[0].direction == .inbox)
        #expect(drafts[0].name == "Alice Smith")
        #expect(drafts[0].address == "alice@x.com")
        #expect(drafts[0].subject == "Hello")
        #expect(drafts[0].date == utc.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 9, minute: 15, second: 0)))
        #expect(drafts[1].direction == .sent)
        #expect(drafts[1].address == "bob@y.com")
        #expect(drafts[1].name == nil)
    }

    @Test func parseOutput_skipsMalformedRecords() {
        let good = record(["in", "<a>", "a@x.com", "S", "2026", "7", "29", "1", "2", "3"])
        let bad = "in\(FS)only\(FS)three"
        let drafts = MailScriptParsing.parseOutput(good + RS + bad + RS, calendar: utc)
        #expect(drafts.count == 1)
    }

    @Test func parseOutput_emptyIsEmpty() {
        #expect(MailScriptParsing.parseOutput("", calendar: utc).isEmpty)
    }

    // MARK: - parseNameAddress

    @Test func parseNameAddress_nameAndAngleAddress() {
        let r = MailScriptParsing.parseNameAddress("Alice Smith <alice@x.com>")
        #expect(r.name == "Alice Smith")
        #expect(r.address == "alice@x.com")
    }

    @Test func parseNameAddress_quotedName() {
        let r = MailScriptParsing.parseNameAddress("\"Bob Jones\" <bob@y.com>")
        #expect(r.name == "Bob Jones")
        #expect(r.address == "bob@y.com")
    }

    @Test func parseNameAddress_bareAddress() {
        let r = MailScriptParsing.parseNameAddress("carol@z.com")
        #expect(r.name == nil)
        #expect(r.address == "carol@z.com")
    }

    // MARK: - dedupeKey

    @Test func dedupeKey_usesMessageIdWhenPresent() {
        #expect(MailScriptParsing.dedupeKey(messageId: "<a@b>", account: "", mailbox: "INBOX",
                                            date: .distantPast, fromAddress: "x@y", subject: "s") == "|INBOX|<a@b>")
    }

    @Test func dedupeKey_fallsBackWhenNoMessageId() {
        #expect(MailScriptParsing.dedupeKey(messageId: "  ", account: "", mailbox: "Sent",
                                            date: Date(timeIntervalSince1970: 100), fromAddress: "x@y", subject: "s")
                == "|Sent|100.0|x@y|s")
    }
}
