import Foundation

// Reads the day's Inbox + Sent messages from Mail.app via AppleScript (Apple events). No credentials
// or network — piggybacks on Mail's already-authenticated accounts. Completion-handler based (no
// Swift.Task); the AppleScript runs on `MailScriptRunner`'s dedicated run-loop thread since the Mail
// query can take a second or two, and results are delivered on the main actor. The intricate text
// handling is in MailScriptParsing.
//
// WHY A DEDICATED THREAD AND NOT A GCD QUEUE: Mail's Apple Event reply is delivered through the
// calling thread's run loop, so executing on a plain background queue (which has none) silently
// returns nothing. WHY NOT THE MAIN THREAD: while NSAppleScript waits it spins a nested Carbon event
// loop, which re-enters whatever else that run loop is servicing — under XCTest that re-entrancy
// deadlocks the test host outright, and in the app it blocks the UI for the length of the query.

enum MailScriptError: Error, Equatable {
    case permissionDenied
    case mailUnavailable
    case scriptError(String)

    var userMessage: String {
        switch self {
        case .permissionDenied: return "Allow gbpDiary to control Mail in System Settings → Privacy & Security → Automation."
        case .mailUnavailable:  return "Mail isn’t available on this Mac."
        case .scriptError(let m): return "Mail returned an error: \(m)"
        }
    }
}

@MainActor final class MailScriptService {
    func fetchDay(_ day: Date, settings: EmailSettings,
                  completion: @escaping (Result<[MailMessageDraft], MailScriptError>) -> Void) {
        #if os(macOS)
        // Targeting one account's Inbox/Sent keeps the query fast (~seconds). It still runs off the
        // main thread (see the file header), so the UI stays live while Mail answers.
        let source = MailScriptParsing.script(forDay: day, accountName: settings.accountName,
                                              inboxMailbox: settings.inboxMailbox, sentMailbox: settings.sentMailbox)
        runScript(source) { completion($0.map { MailScriptParsing.parseOutput($0) }) }
        #else
        completion(.failure(.mailUnavailable))
        #endif
    }

    /// Fetches Inbox + Sent over the half-open day window `[rangeStart, rangeEnd)` in one AppleScript
    /// call (used by auto-ingest to catch up several days). Delivered on the main actor.
    func fetchRange(rangeStart: Date, rangeEnd: Date, settings: EmailSettings,
                    completion: @escaping (Result<[MailMessageDraft], MailScriptError>) -> Void) {
        #if os(macOS)
        let source = MailScriptParsing.script(rangeStart: rangeStart, rangeEnd: rangeEnd,
                                              accountName: settings.accountName,
                                              inboxMailbox: settings.inboxMailbox, sentMailbox: settings.sentMailbox)
        runScript(source) { completion($0.map { MailScriptParsing.parseOutput($0) }) }
        #else
        completion(.failure(.mailUnavailable))
        #endif
    }

    /// Opens a stored email in Mail: resolves the real mailbox/account (the stored `mailbox` is a
    /// placeholder), then opens by Mail's integer id. Completion is delivered on the main actor.
    func openMessage(_ email: EmailMessage, completion: @escaping (Result<Void, MailScriptError>) -> Void) {
        let settings = EmailSettingsStore.load()
        let mailbox = email.direction == .inbox ? settings.inboxMailbox : settings.sentMailbox
        let account = email.account.isEmpty ? settings.accountName : email.account
        let id = email.messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            completion(.failure(.scriptError("this email has no stored message id to open")))
            return
        }
        openMessage(account: account, mailbox: mailbox, id: id, completion: completion)
    }

    /// Fetches one email's plain-text body from local Mail (transient — for on-device summarisation;
    /// never stored). Resolves the real mailbox/account like `openMessage(_:)`.
    func fetchContent(_ email: EmailMessage, completion: @escaping (Result<String, MailScriptError>) -> Void) {
        let settings = EmailSettingsStore.load()
        let mailbox = email.direction == .inbox ? settings.inboxMailbox : settings.sentMailbox
        let account = email.account.isEmpty ? settings.accountName : email.account
        let id = email.messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            completion(.failure(.scriptError("this email has no stored message id")))
            return
        }
        #if os(macOS)
        let source = MailScriptParsing.messageContentScript(account: account, mailbox: mailbox, id: id)
        runScript(source, completion)
        #else
        completion(.failure(.mailUnavailable))
        #endif
    }

    /// Opens a message by account + mailbox + Mail integer id, bringing Mail forward.
    func openMessage(account: String, mailbox: String, id: String,
                     completion: @escaping (Result<Void, MailScriptError>) -> Void) {
        #if os(macOS)
        let source = MailScriptParsing.openMessageScript(account: account, mailbox: mailbox, id: id)
        runScript(source) { completion($0.map { _ in () }) }
        #else
        completion(.failure(.mailUnavailable))
        #endif
    }

    /// Names of the user's Mail accounts (for the Settings picker).
    func listAccounts(completion: @escaping (Result<[String], MailScriptError>) -> Void) {
        runList(MailScriptParsing.accountsScript(), completion)
    }

    /// Mailbox names of one account (for the Settings pickers).
    func listMailboxes(account: String, completion: @escaping (Result<[String], MailScriptError>) -> Void) {
        runList(MailScriptParsing.mailboxesScript(accountName: account), completion)
    }

    private func runList(_ source: String, _ completion: @escaping (Result<[String], MailScriptError>) -> Void) {
        #if os(macOS)
        runScript(source) { completion($0.map { MailScriptParsing.parseNameList($0) }) }
        #else
        completion(.failure(.mailUnavailable))
        #endif
    }

    #if os(macOS)
    /// Runs `source` on the dedicated script thread and delivers the result on the main actor.
    fileprivate func runScript(_ source: String,
                               _ completion: @escaping (Result<String, MailScriptError>) -> Void) {
        MailScriptRunner.shared.run(source, completion: completion)
    }

    /// Runs the AppleScript synchronously on the calling thread (must be one with a live run loop —
    /// see `MailScriptRunner`) and returns its output text or a mapped error.
    fileprivate nonisolated static func run(_ source: String) -> Result<String, MailScriptError> {
        guard let script = NSAppleScript(source: source) else { return .failure(.scriptError("could not compile script")) }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "unknown error"
            if code == -1743 { return .failure(.permissionDenied) }   // errAEEventNotPermitted (Automation denied)
            return .failure(.scriptError("[\(code)] \(message)"))
        }
        return .success(descriptor.stringValue ?? "")
    }
    #endif
}

#if os(macOS)
/// Owns the one background thread that every Mail AppleScript runs on.
///
/// The thread keeps a live run loop (parked on a permanent `NSMachPort` source) because that is how
/// Mail's Apple Event reply reaches `NSAppleScript` — on a plain GCD queue, with no run loop, the
/// call silently returns nothing. Being a single thread it is also serial, which `NSAppleScript`
/// requires: it is not thread-safe. Completions are hopped back to the main actor.
private final class MailScriptRunner: NSObject, @unchecked Sendable {
    static let shared = MailScriptRunner()

    private var thread: Thread!

    private override init() {
        super.init()
        thread = Thread(target: self, selector: #selector(serviceRunLoop), object: nil)
        thread.name = "io.github.gbpoole.gbpDiary.mailscript"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    @objc private func serviceRunLoop() {
        let runLoop = RunLoop.current
        // A permanent source keeps `run(mode:before:)` from returning immediately with no input.
        runLoop.add(NSMachPort(), forMode: .default)
        while !Thread.current.isCancelled {
            runLoop.run(mode: .default, before: .distantFuture)
        }
    }

    /// Executes `source` on the script thread; `completion` is called on the main actor.
    func run(_ source: String, completion: @escaping (Result<String, MailScriptError>) -> Void) {
        let request = MailScriptRequest(source: source, completion: completion)
        perform(#selector(execute(_:)), on: thread, with: request, waitUntilDone: false)
    }

    @objc private func execute(_ request: MailScriptRequest) {
        let result = MailScriptService.run(request.source)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { request.completion(result) }
        }
    }
}

/// Carries one script + its completion across to the script thread (`perform(_:on:with:)` takes an
/// object). The completion is only ever invoked back on the main actor.
private final class MailScriptRequest: NSObject, @unchecked Sendable {
    let source: String
    let completion: (Result<String, MailScriptError>) -> Void

    init(source: String, completion: @escaping (Result<String, MailScriptError>) -> Void) {
        self.source = source
        self.completion = completion
    }
}
#endif
