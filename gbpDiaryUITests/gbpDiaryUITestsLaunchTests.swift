//
//  gbpDiaryUITestsLaunchTests.swift
//  gbpDiaryUITests
//
//  Created by Gregory Brian Poole on 22/5/2026.
//

import XCTest

final class gbpDiaryUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchConfigurationRunsSingleUIConfiguration() throws {
        XCTAssertFalse(Self.runsForEachTargetApplicationUIConfiguration)
    }
}
