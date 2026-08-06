import Foundation

// Pure, Foundation-only logic for the Mail.app AppleScript bridge: builds the AppleScript source for
// a day's Inbox + Sent messages, and parses its delimited output. No AppleScript execution here (that
// lives in MailScriptService), so this is fully unit-testable.

/// One message read from Mail. `address`/`name` are the *other party* (Inbox → sender; Sent → first recipient).
struct MailMessageDraft: Equatable {
    var messageId: String
    var address: String
    var name: String?
    var subject: String
    var date: Date
    var direction: EmailDirection
}

enum MailScriptParsing {
    static let fieldSep = "\u{1F}"   // ASCII unit separator
    static let recordSep = "\u{1E}"  // ASCII record separator

    /// AppleScript that emits the day's Inbox + Sent messages (for one account) as `field`-/`record`-
    /// separated text. Each record: dir · message-id · party · subject · year · month · day · h · m · s.
    /// Targets a specific account's mailboxes (not the giant unified inbox) so the scan stays fast.
    nonisolated static func script(forDay day: Date,
                                   accountName: String = "Exchange",
                                   inboxMailbox: String = "Inbox",
                                   sentMailbox: String = "Sent Items",
                                   calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: day)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return script(rangeStart: start, rangeEnd: next, accountName: accountName,
                      inboxMailbox: inboxMailbox, sentMailbox: sentMailbox, calendar: calendar)
    }

    /// Like `script(forDay:)` but over a half-open `[rangeStart, rangeEnd)` window (both normalised to
    /// start-of-day) — used to fetch several days at once (auto-ingest).
    nonisolated static func script(rangeStart: Date, rangeEnd: Date,
                                   accountName: String = "Exchange",
                                   inboxMailbox: String = "Inbox",
                                   sentMailbox: String = "Sent Items",
                                   calendar: Calendar = .current) -> String {
        // Full datetime bounds (not day-normalised) so an incremental "since last fetch" window works.
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let s = calendar.dateComponents(fields, from: rangeStart)
        let n = calendar.dateComponents(fields, from: rangeEnd)
        let d1 = "mkDateTime(\(s.year!), \(s.month!), \(s.day!), \(s.hour!), \(s.minute!), \(s.second!))"
        let d2 = "mkDateTime(\(n.year!), \(n.month!), \(n.day!), \(n.hour!), \(n.minute!), \(n.second!))"
        let acc = escape(accountName), inbox = escape(inboxMailbox), sent = escape(sentMailbox)
        return """
        set FS to (ASCII character 31)
        set RS to (ASCII character 30)
        set d1 to my \(d1)
        set d2 to my \(d2)
        set out to ""
        with timeout of 90 seconds
            tell application "Mail"
                set acc to account "\(acc)"
                -- The account's own addresses, so a message that looped back to the Inbox because we
                -- sent it to a mailing list we're on can be skipped (the Sent copy represents it).
                set myAddrs to {}
                try
                    set myAddrs to (get email addresses of acc)
                end try
                try
                    -- Materialize the filter result once, then iterate concrete references (iterating the
                    -- `whose` specifier directly re-scans the whole mailbox per access — pathologically slow).
                    set inMsgs to (messages of mailbox "\(inbox)" of acc whose date received ≥ d1 and date received < d2)
                    repeat with m in inMsgs
                        if not my senderIsMine(m, myAddrs) then
                            set out to out & my rec("in", m, FS) & RS
                        end if
                    end repeat
                end try
                try
                    set sentMsgs to (messages of mailbox "\(sent)" of acc whose date sent ≥ d1 and date sent < d2)
                    repeat with m in sentMsgs
                        set out to out & my rec("sent", m, FS) & RS
                    end repeat
                end try
            end tell
        end timeout
        return out

        on mkDateTime(y, mo, d, h, mi, s)
            set dt to current date
            set day of dt to 1
            set year of dt to y
            set month of dt to mo
            set day of dt to d
            set time of dt to (h * 3600 + mi * 60 + s)
            return dt
        end mkDateTime

        on senderIsMine(m, myAddrs)
            set snd to ""
            tell application "Mail"
                try
                    set snd to (sender of m) as string
                end try
            end tell
            if snd is "" then return false
            repeat with a in myAddrs
                set addr to (a as string)
                if addr is not "" and snd contains addr then return true
            end repeat
            return false
        end senderIsMine

        on rec(dir, m, FS)
            tell application "Mail"
                -- Use Mail's fast integer `id` (unique per message) for dedupe — NOT `message id` (the
                -- RFC header), which forces a slow per-message header fetch.
                set mid to ""
                try
                    set mid to (id of m) as string
                end try
                set subj to ""
                try
                    set subj to (subject of m) as string
                end try
                if dir is "in" then
                    set party to ""
                    try
                        set party to (sender of m) as string
                    end try
                    set theDate to date received of m
                else
                    set party to ""
                    try
                        set r to item 1 of (to recipients of m)
                        set pn to ""
                        try
                            set pn to (name of r) as string
                        end try
                        set pa to (address of r) as string
                        if pn is "" then
                            set party to pa
                        else
                            set party to pn & " <" & pa & ">"
                        end if
                    end try
                    set theDate to date sent of m
                end if
                set y to (year of theDate) as string
                set mo to ((month of theDate) as integer) as string
                set dd to (day of theDate) as string
                set hh to (hours of theDate) as string
                set mm to (minutes of theDate) as string
                set ss to (seconds of theDate) as string
                return dir & FS & mid & FS & party & FS & subj & FS & y & FS & mo & FS & dd & FS & hh & FS & mm & FS & ss
            end tell
        end rec
        """
    }

    /// AppleScript that opens one message in Mail (by Mail's integer `id` within an account's mailbox)
    /// and brings Mail forward. `account`/`mailbox` are escaped; `id` is embedded unquoted (integer).
    nonisolated static func openMessageScript(account: String, mailbox: String, id: String) -> String {
        """
        tell application "Mail"
            set acc to account "\(escape(account))"
            set theMsg to (first message of mailbox "\(escape(mailbox))" of acc whose id is \(id))
            open theMsg
            activate
        end tell
        """
    }

    /// AppleScript returning the plain-text body (`content`) of one message, located by account +
    /// mailbox + Mail's integer id. Used transiently for on-device summarisation (never stored).
    nonisolated static func messageContentScript(account: String, mailbox: String, id: String) -> String {
        """
        with timeout of 30 seconds
            tell application "Mail"
                set acc to account "\(escape(account))"
                set theMsg to (first message of mailbox "\(escape(mailbox))" of acc whose id is \(id))
                return (content of theMsg) as string
            end tell
        end timeout
        """
    }

    /// AppleScript returning the names of every Mail account, one per line.
    nonisolated static func accountsScript() -> String {
        """
        tell application "Mail"
            set AppleScript's text item delimiters to (ASCII character 10)
            set out to (name of every account) as string
            set AppleScript's text item delimiters to ""
            return out
        end tell
        """
    }

    /// AppleScript returning the names of every mailbox of one account, one per line.
    nonisolated static func mailboxesScript(accountName: String) -> String {
        """
        tell application "Mail"
            set AppleScript's text item delimiters to (ASCII character 10)
            set out to (name of every mailbox of account "\(escape(accountName))") as string
            set AppleScript's text item delimiters to ""
            return out
        end tell
        """
    }

    /// Splits a newline-separated name list, trimming blanks.
    nonisolated static func parseNameList(_ raw: String) -> [String] {
        raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Escapes `\` and `"` for embedding a name in an AppleScript quoted string.
    private nonisolated static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Parses the AppleScript output into drafts. Malformed records are skipped.
    nonisolated static func parseOutput(_ raw: String, calendar: Calendar = .current) -> [MailMessageDraft] {
        raw.components(separatedBy: recordSep).compactMap { record in
            let f = record.components(separatedBy: fieldSep)
            guard f.count == 10 else { return nil }
            let direction: EmailDirection = f[0] == "sent" ? .sent : .inbox
            let (name, address) = parseNameAddress(f[2])
            var comps = DateComponents()
            comps.year = Int(f[4]); comps.month = Int(f[5]); comps.day = Int(f[6])
            comps.hour = Int(f[7]); comps.minute = Int(f[8]); comps.second = Int(f[9])
            guard let date = calendar.date(from: comps) else { return nil }
            return MailMessageDraft(messageId: f[1].trimmingCharacters(in: .whitespacesAndNewlines),
                                    address: address, name: name,
                                    subject: f[3], date: date, direction: direction)
        }
    }

    /// Splits `Alice Smith <a@x.com>` / `"Alice" <a@x.com>` / bare `a@x.com` into (name?, address).
    nonisolated static func parseNameAddress(_ s: String) -> (name: String?, address: String) {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = trimmed.lastIndex(of: "<"), let close = trimmed.lastIndex(of: ">"), open < close {
            let address = String(trimmed[trimmed.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            var name = String(trimmed[trimmed.startIndex..<open]).trimmingCharacters(in: .whitespaces)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return (name.isEmpty ? nil : name, address)
        }
        return (nil, trimmed)
    }

    /// Stable upsert key: `account|mailbox|<message-id>` when present, else a content fallback.
    nonisolated static func dedupeKey(messageId: String, account: String, mailbox: String,
                                      date: Date, fromAddress: String, subject: String) -> String {
        let mid = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mid.isEmpty { return "\(account)|\(mailbox)|\(mid)" }
        return "\(account)|\(mailbox)|\(date.timeIntervalSince1970)|\(fromAddress)|\(subject)"
    }
}
