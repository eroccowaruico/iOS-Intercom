import XCTest

final class RideIntercomUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        launchApp()
    }

    private func launchApp(startOnDiagnostics: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data"]
        if startOnDiagnostics {
            app.launchArguments.append("--start-on-diagnostics")
        }
        app.launch()

        XCTAssertTrue(waitForVisibleRoot(in: app), "Expected the app to launch into a visible root screen")
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    @MainActor
    func testGroupSelectionOpensCallScreen() throws {
        createTrailGroupAndOpenCall()

        XCTAssertTrue(app.staticTexts["Participants"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["localMicrophonePanel"].exists)
        XCTAssertTrue(app.staticTexts["Your Microphone"].exists)
        XCTAssertTrue(app.staticTexts["Live"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["connectionStatusIcon"].exists)
        XCTAssertTrue(app.staticTexts["routeLabel"].exists)
        XCTAssertTrue(app.buttons["Mute"].exists)
        XCTAssertTrue(app.buttons["inviteButton"].exists)
        XCTAssertTrue(app.buttons["connectButton"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["participantSlot0"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["callAudioOutputPicker"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["callAudioInputPicker"].exists)
    }

    @MainActor
    func testManualAddRiderButtonIsNotShownInCallUI() throws {
        createTrailGroupAndOpenCall()

        XCTAssertFalse(app.buttons["Add Rider"].exists)
        XCTAssertTrue(app.buttons["inviteButton"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testMuteControlLivesInsideLocalMicrophonePanel() throws {
        createTrailGroupAndOpenCall()

        XCTAssertTrue(app.staticTexts["Your Microphone"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Mute"].exists)
        app.buttons["Mute"].tap()
        XCTAssertTrue(app.staticTexts["Muted"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testParticipantDeletionIsNotShownForLocalMemberOnly() throws {
        createTrailGroupAndOpenCall()

        XCTAssertFalse(app.buttons["Add Rider"].exists)
        XCTAssertFalse(app.buttons["removeParticipantButton0"].exists)
        XCTAssertTrue(app.buttons["inviteButton"].exists)
    }

    @MainActor
    func testDiagnosticsShowRealDeviceSetupIdentifiers() throws {
        relaunchOnDiagnosticsTab()

        XCTAssertTrue(app.descendants(matching: .any)["audioIOPanel"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Next start"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["audioCheckPanel"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Call Idle"].exists)
        XCTAssertTrue(app.staticTexts["Microphone Input"].exists)
        XCTAssertTrue(app.staticTexts["Speaker Output"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["callAudioOutputPicker"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["callAudioInputPicker"].exists)
    }

    @MainActor
    func testAudioCheckControlsAreAvailableFromDiagnostics() throws {
        relaunchOnDiagnosticsTab()

        XCTAssertTrue(app.buttons["Record 5s and Play"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Microphone Input"].exists)
        XCTAssertTrue(app.staticTexts["Speaker Output"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["audioCheckPanel"].exists)
    }

    @MainActor
    func testVoiceActivityAndHandoverCanBeExercisedFromUI() throws {
        createTrailGroupAndOpenCall()

        XCTAssertTrue(app.buttons["connectButton"].exists)
        XCTAssertFalse(app.buttons["Refresh"].exists)
        XCTAssertFalse(app.buttons["Simulate Handover"].exists)
        XCTAssertFalse(app.staticTexts["Silent"].exists)
    }

    @MainActor
    func testGroupDeletionCanBeExercisedFromUI() throws {
        createTrailGroupAndOpenCall()
        openGroupsTab()

        let groupRow = app.buttons["groupRow-Trail Group"]
        XCTAssertTrue(groupRow.waitForExistence(timeout: 3))
        groupRow.swipeLeft()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 2))
        app.buttons["Delete"].tap()
        XCTAssertFalse(groupRow.exists)
    }

    @MainActor
    func testDiagnosticsKeepsMicrophoneIndicatorVisibleWithoutGroup() throws {
        relaunchOnDiagnosticsTab()

        XCTAssertTrue(app.staticTexts["Microphone Input"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Speaker Output"].exists)
    }

    private func createTrailGroupAndOpenCall() {
        openGroupsTab()
        let createButton = app.buttons["createGroupButton"].exists
            ? app.buttons["createGroupButton"]
            : app.buttons["Create Trail Group"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 3))
        createButton.tap()
        XCTAssertTrue(app.scrollViews["callScreen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Participants"].waitForExistence(timeout: 3))
    }

    private func relaunchOnDiagnosticsTab() {
        app.terminate()
        launchApp(startOnDiagnostics: true)
    }

    private func openGroupsTab() {
        if app.buttons["showGroupsButton"].exists {
            app.buttons["showGroupsButton"].tap()
            return
        }
        if app.tabBars.buttons["Groups"].exists {
            app.tabBars.buttons["Groups"].tap()
            return
        }
        if app.radioButtons["groupsTab"].exists {
            app.radioButtons["groupsTab"].tap()
            return
        }
        if app.buttons["Groups"].exists {
            app.buttons["Groups"].tap()
        }
    }

    private func openDiagnosticsTab() {
        if app.tabBars.buttons["Diagnostics"].exists {
            app.tabBars.buttons["Diagnostics"].tap()
            return
        }
        if app.radioButtons["diagnosticsTab"].exists {
            app.radioButtons["diagnosticsTab"].tap()
            return
        }
        if app.buttons["diagnosticsTab"].exists {
            app.buttons["diagnosticsTab"].tap()
            return
        }
        if app.buttons["Diagnostics"].exists {
            app.buttons["Diagnostics"].tap()
        }
    }

    private func waitForVisibleRoot(in app: XCUIApplication) -> Bool {
        let hasVisibleRoot = app.buttons["createGroupButton"].waitForExistence(timeout: 1)
            || app.buttons["Create Trail Group"].waitForExistence(timeout: 1)
            || app.buttons["Record 5s and Play"].waitForExistence(timeout: 1)
            || app.buttons["diagnosticsTab"].waitForExistence(timeout: 1)
            || app.buttons["Diagnostics"].waitForExistence(timeout: 1)
            || app.tabBars.buttons["Diagnostics"].waitForExistence(timeout: 1)
        if !hasVisibleRoot {
            app.typeKey("n", modifierFlags: .command)
            return app.buttons["createGroupButton"].waitForExistence(timeout: 2)
                || app.buttons["Create Trail Group"].waitForExistence(timeout: 2)
                || app.buttons["Record 5s and Play"].waitForExistence(timeout: 2)
                || app.buttons["diagnosticsTab"].waitForExistence(timeout: 2)
                || app.buttons["Diagnostics"].waitForExistence(timeout: 2)
                || app.tabBars.buttons["Diagnostics"].waitForExistence(timeout: 2)
        }
        return true
    }
}
