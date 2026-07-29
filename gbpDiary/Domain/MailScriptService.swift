import Foundation

// Reads the day's Inbox + Sent messages from Mail.app via AppleScript (Apple events). No credentials
// or network — piggybacks on Mail's already-authenticated accounts. Completion-handler based (no
// Swift.Task); the AppleScript runs on a background queue since the Mail query can take a second or
// two, and results are delivered on the main actor. The intricate text handling is in MailScriptParsing.

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
        // Apple events (and the one-time Automation prompt) only work reliably on the main thread —
        // background execution silently returns nothing. Targeting one account's Inbox/Sent keeps the
        // query fast (~seconds), so the brief main-thread block is acceptable. The async hop lets the UI
        // paint the "Fetching…" state before the (blocking) script runs.
        let source = MailScriptParsing.script(forDay: day, accountName: settings.accountName,
                                              inboxMailbox: settings.inboxMailbox, sentMailbox: settings.sentMailbox)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                completion(Self.run(source).map { MailScriptParsing.parseOutput($0) })
            }
        }
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
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                completion(Self.run(source).map { MailScriptParsing.parseNameList($0) })
            }
        }
        #else
        completion(.failure(.mailUnavailable))
        #endif
    }

    #if os(macOS)
    /// Runs the AppleScript synchronously (off the main thread) and returns its output text or a mapped error.
    private nonisolated static func run(_ source: String) -> Result<String, MailScriptError> {
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
