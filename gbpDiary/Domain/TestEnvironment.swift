import Foundation

/// Detects that this process is hosting an injected XCTest bundle.
///
/// Unit tests run *inside* the real app, so the global background drivers placed in
/// `WorkspaceView` (`EmailFetchDriver`, `ChatIndexDriver`, …) would otherwise start during a
/// test run. That is fatal, not merely slow: `MailScriptService` executes its `NSAppleScript`
/// on the main thread, and AppleScript spins a nested Carbon event loop while it waits for
/// Mail to reply. XCTest's start source fires inside that nested loop and then blocks the main
/// thread, so the AppleScript reply can never be delivered — the run deadlocks and fails with
/// "The test runner timed out while preparing to run tests."
enum TestEnvironment {
    /// True while the app is hosting a unit-test bundle.
    static var isRunningUnitTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
