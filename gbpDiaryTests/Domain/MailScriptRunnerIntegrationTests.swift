import XCTest
@testable import gbpDiary

/// Opt-in check that the Mail AppleScript really works from `MailScriptRunner`'s background
/// run-loop thread. It drives Mail, so it is skipped unless explicitly enabled:
///
///     defaults write io.github.gbpoole.gbpDiary mailIntegrationTests -bool YES
///     xcodebuild -scheme gbpDiary -destination 'platform=macOS' \
///       -only-testing:gbpDiaryTests/MailScriptRunnerIntegrationTests test
///     defaults delete io.github.gbpoole.gbpDiary mailIntegrationTests
///
/// It guards the specific regression risk in moving execution off the main thread: an Apple Event
/// reply is delivered through the calling thread's run loop, so a thread without one comes back
/// empty rather than failing loudly.
final class MailScriptRunnerIntegrationTests: XCTestCase {

    @MainActor
    func testListAccounts_returnsDataFromTheBackgroundRunLoopThread() throws {
        try XCTSkipUnless(UserDefaults.standard.bool(forKey: "mailIntegrationTests"),
                          "Mail integration test not enabled")

        let expectation = expectation(description: "listAccounts completes")
        var received: Result<[String], MailScriptError>?
        MailScriptService().listAccounts { result in
            received = result
            expectation.fulfill()
        }
        // Completing at all proves no main-thread deadlock: this wait spins the main run loop.
        wait(for: [expectation], timeout: 60)

        switch received {
        case .success(let accounts):
            XCTAssertFalse(accounts.isEmpty,
                           "Empty account list is the 'silently returns nothing' failure mode.")
        case .failure(let error):
            XCTFail("Mail script failed: \(error)")
        case nil:
            XCTFail("No result delivered")
        }
    }
}
