import XCTest
@testable import gbpDiary

/// Guards the switch that keeps the global background drivers (Mail AppleScript fetch, semantic
/// indexing, recurrence sweeps) out of the unit-test host. If this ever reports false, the test
/// run deadlocks in `MailScriptService`'s main-thread AppleScript nested event loop.
final class TestEnvironmentTests: XCTestCase {


    func testIsRunningUnitTests_isTrueInsideTheTestHost() {
        XCTAssertTrue(TestEnvironment.isRunningUnitTests,
                      "Background drivers would start during tests and deadlock the run.")
    }
}
