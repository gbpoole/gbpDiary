import Foundation
import Testing
@testable import gbpDiary

struct EmailThreadGraphTests {
    private func m(_ id: String, msg: String = "", inReplyTo: String? = nil,
                   refs: [String] = [], subject: String = "") -> ThreadableMessage {
        ThreadableMessage(id: id, messageId: msg, inReplyTo: inReplyTo, references: refs, subject: subject)
    }
    private func keys(_ msgs: [ThreadableMessage]) -> [String: String] { EmailThreadGraph.assign(msgs) }

    @Test func replyChainUnites() {
        let a = m("a", msg: "M1", subject: "Plan")
        let b = m("b", msg: "M2", inReplyTo: "M1", refs: ["M1"], subject: "Re: Plan")
        let c = m("c", msg: "M3", inReplyTo: "M2", refs: ["M1", "M2"], subject: "Re: Plan")
        let k = keys([a, b, c])
        #expect(k["a"] == k["b"])
        #expect(k["b"] == k["c"])
    }

    @Test func subjectChangeMidThreadStaysOneThread() {
        // The reply link wins even when the subject was edited.
        let a = m("a", msg: "M1", subject: "Budget 2026")
        let b = m("b", msg: "M2", inReplyTo: "M1", subject: "totally different subject")
        let k = keys([a, b])
        #expect(k["a"] == k["b"])
    }

    @Test func multiPartyExchangeUnites() {
        // Three replies to the same root from different senders → one thread.
        let root = m("r", msg: "M1", subject: "ADACS")
        let jarrod = m("j", msg: "M2", refs: ["M1"], subject: "Re: ADACS")
        let cheryl = m("c", msg: "M3", refs: ["M1"], subject: "Re: ADACS")
        let k = keys([root, jarrod, cheryl])
        #expect(k["r"] == k["j"])
        #expect(k["j"] == k["c"])
    }

    @Test func recurringSubjectWithoutLinksStaysSeparate() {
        // Two independent "Standup" mails, each with its own Message-ID and no references → separate threads.
        let a = m("a", msg: "M1", subject: "Standup")
        let b = m("b", msg: "M2", subject: "Standup")
        let k = keys([a, b])
        #expect(k["a"] != k["b"])
    }

    @Test func headerlessFallsBackToSubject() {
        // No reply headers at all → group by normalized subject; different subjects split; blank stands alone.
        let a = m("a", subject: "Re: Weekly")
        let b = m("b", subject: "Weekly")
        let c = m("c", subject: "Other")
        let blank1 = m("z1", subject: "")
        let blank2 = m("z2", subject: "")
        let k = keys([a, b, c, blank1, blank2])
        #expect(k["a"] == k["b"])      // same normalized subject
        #expect(k["a"] != k["c"])
        #expect(k["z1"] != k["z2"])    // blank subjects don't merge
    }

    @Test func assignmentIsDeterministicRegardlessOfOrder() {
        let a = m("a", msg: "M1", subject: "X")
        let b = m("b", msg: "M2", refs: ["M1"], subject: "Re: X")
        let c = m("c", msg: "M3", refs: ["M2"], subject: "Re: X")
        let forward = keys([a, b, c])
        let reversed = keys([c, b, a])
        #expect(forward == reversed)   // stable min-id canonical key
    }
}
