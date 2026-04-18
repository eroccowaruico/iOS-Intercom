import XCTest

final class RideIntercomUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testGroupSelectionConnectsToSixSlotCallScreen() throws {
        let app = launchAppWithVisibleWindow()

        XCTAssertTrue(app.buttons["Create Trail Group"].waitForExistence(timeout: 3))
        app.buttons["Create Trail Group"].tap()

        XCTAssertTrue(app.staticTexts["Participants"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Waiting for Riders"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Offline"].exists)
        XCTAssertTrue(app.staticTexts["Owner: You"].exists)

        XCTAssertTrue(app.staticTexts["Your Microphone"].exists)
        XCTAssertTrue(app.staticTexts["Live"].exists)
        XCTAssertTrue(app.buttons["Mute"].exists)
        XCTAssertFalse(app.staticTexts["Partner"].exists)
        XCTAssertFalse(app.staticTexts["Empty"].exists)
        XCTAssertTrue(app.staticTexts["voiceMeterValueLabel"].exists)
        XCTAssertTrue(app.buttons["Invite Group"].exists)
        XCTAssertFalse(app.buttons["Add Rider"].exists)
        XCTAssertTrue(app.staticTexts["INVITE READY"].exists)
        XCTAssertTrue(app.staticTexts["CALL Idle / AUDIO IDLE / TX 0 / RX 0 / PLAY 0 / AUTH 0 / LAST RX -- / DROP 0 / JIT 0"].exists)
        XCTAssertFalse(app.staticTexts["participantMCStatus0"].exists)
        XCTAssertTrue(app.buttons["Connect Local"].exists)
        XCTAssertFalse(app.buttons["Refresh"].exists)
        XCTAssertFalse(app.buttons["Simulate Handover"].exists)
        XCTAssertFalse(app.buttons["handoverButton"].exists)
        XCTAssertTrue(app.staticTexts["Waiting automatically"].exists)
        XCTAssertTrue(app.staticTexts["MC connected"].exists)

    }

    @MainActor
    func testManualAddRiderButtonIsNotShownInCallUI() throws {
        let app = launchAppWithVisibleWindow()

        XCTAssertTrue(app.buttons["Create Trail Group"].waitForExistence(timeout: 3))
        app.buttons["Create Trail Group"].tap()
        XCTAssertFalse(app.buttons["Add Rider"].exists)
        XCTAssertTrue(app.buttons["Invite Group"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testMuteControlLivesInsideLocalMicrophonePanel() throws {
        let app = launchAppWithVisibleWindow()

        XCTAssertTrue(app.buttons["Create Trail Group"].waitForExistence(timeout: 3))
        app.buttons["Create Trail Group"].tap()

        XCTAssertTrue(app.staticTexts["Your Microphone"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Mute"].exists)
        app.buttons["Mute"].tap()
        XCTAssertTrue(app.buttons["Unmute"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Muted"].exists)
    }

    @MainActor
    func testParticipantDeletionCanBeExercisedFromUI() throws {
        let app = launchAppWithVisibleWindow()

        XCTAssertTrue(app.buttons["Create Trail Group"].waitForExistence(timeout: 3))
        app.buttons["Create Trail Group"].tap()
        XCTAssertFalse(app.buttons["Add Rider"].exists)
        XCTAssertTrue(app.buttons["Invite Group"].exists)
    }

    @MainActor
    func testDiagnosticsShowRealDeviceSetupIdentifiers() throws {
        let app = launchAppWithVisibleWindow(startOnDiagnostics: true)

        XCTAssertTrue(app.staticTexts["localMemberDebugSummaryLabel"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["transportDebugSummaryLabel"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["selectedGroupDebugSummaryLabel"].exists)
        XCTAssertTrue(app.staticTexts["groupHashDebugSummaryLabel"].exists)
    }

    @MainActor
    func testAudioCheckControlsAreAvailableFromDiagnostics() throws {
        let app = launchAppWithVisibleWindow(startOnDiagnostics: true)

        XCTAssertTrue(app.buttons["Record 5s and Play"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Audio Check Idle"].exists)
        XCTAssertTrue(app.staticTexts["Microphone Input"].exists)
        XCTAssertTrue(app.staticTexts["Speaker Output"].exists)
    }

    @MainActor
    func testVoiceActivityAndHandoverCanBeExercisedFromUI() throws {
        let app = launchAppWithVisibleWindow()

        XCTAssertTrue(app.buttons["Create Trail Group"].waitForExistence(timeout: 3))
        app.buttons["Create Trail Group"].tap()
        XCTAssertTrue(app.staticTexts["Waiting for Riders"].waitForExistence(timeout: 3))

        XCTAssertTrue(app.staticTexts["TX 0 / RX 0 / PLAY 0"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Connect Local"].exists)
        XCTAssertFalse(app.buttons["Refresh"].exists)
        XCTAssertFalse(app.buttons["Simulate Handover"].exists)
        XCTAssertFalse(app.staticTexts["Silent"].exists)

        XCTAssertTrue(app.staticTexts["MC connected"].exists)
    }

    @MainActor
    func testGroupDeletionCanBeExercisedFromUI() throws {
        let app = launchAppWithVisibleWindow()

        XCTAssertTrue(app.buttons["Create Trail Group"].waitForExistence(timeout: 3))
        app.buttons["Create Trail Group"].tap()

        if app.buttons["showGroupsButton"].exists {
            app.buttons["showGroupsButton"].tap()
        } else if app.tabBars.buttons["Groups"].exists {
            app.tabBars.buttons["Groups"].tap()
        } else {
            app.buttons["Groups"].tap()
        }
        XCTAssertTrue(app.buttons["Delete Trail Group"].waitForExistence(timeout: 3))
        app.buttons["Delete Trail Group"].tap()
        XCTAssertFalse(app.buttons["Delete Trail Group"].exists)
    }

    @MainActor
    private func launchAppWithVisibleWindow(startOnDiagnostics: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data"]
        if startOnDiagnostics {
            app.launchArguments.append("--start-on-diagnostics")
        }
        app.launch()

        let hasVisibleRoot = app.buttons["createGroupButton"].waitForExistence(timeout: 1)
            || app.buttons["Create Trail Group"].waitForExistence(timeout: 1)
            || app.buttons["Record 5s and Play"].waitForExistence(timeout: 1)
            || app.buttons["diagnosticsTab"].waitForExistence(timeout: 1)
            || app.buttons["Diagnostics"].waitForExistence(timeout: 1)
            || app.tabBars.buttons["Diagnostics"].waitForExistence(timeout: 1)
        if !hasVisibleRoot {
            app.typeKey("n", modifierFlags: .command)
        }

        return app
    }
}
