//
//  RideIntercomUITestsLaunchTests.swift
//  RideIntercomUITests
//
//  Created by Naohito Sasao on 2026/04/18.
//

import XCTest

final class RideIntercomUITestsLaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data"]
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(
            waitForVisibleRoot(in: app),
            "Expected the app to launch into a visible root screen"
        )
    }

    private func waitForVisibleRoot(in app: XCUIApplication) -> Bool {
        app.buttons["createGroupButton"].firstMatch.waitForExistence(timeout: 2)
            || app.buttons["Create Trail Group"].firstMatch.waitForExistence(timeout: 2)
            || app.descendants(matching: .any)["liveTransmitPipelineView"].firstMatch.waitForExistence(timeout: 2)
            || app.descendants(matching: .any)["settingsScrollView"].firstMatch.waitForExistence(timeout: 2)
            || app.buttons["diagnosticsTab"].firstMatch.waitForExistence(timeout: 2)
            || app.buttons["Diagnostics"].firstMatch.waitForExistence(timeout: 2)
            || app.radioButtons["diagnosticsTab"].firstMatch.waitForExistence(timeout: 2)
            || app.staticTexts["Recent Groups"].firstMatch.waitForExistence(timeout: 2)
    }
}
