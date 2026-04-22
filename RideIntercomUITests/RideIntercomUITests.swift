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
        XCTAssertFalse(app.descendants(matching: .any)["localMicrophonePanel"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["localMicrophoneMeter"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Live"].exists)
        XCTAssertTrue(app.staticTexts["callPresenceLabel"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["routeLabel"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["localMicrophoneMuteButton"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Mute Output"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["inviteButton"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["connectButton"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["emptyRemoteParticipantsLabel"].waitForExistence(timeout: 3))
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
    func testMuteControlLivesWithHeaderMicrophoneMeter() throws {
        createTrailGroupAndOpenCall()

        XCTAssertTrue(app.descendants(matching: .any)["localMicrophoneMeter"].waitForExistence(timeout: 3))
        let muteButton = app.buttons["localMicrophoneMuteButton"]
        XCTAssertTrue(muteButton.waitForExistence(timeout: 3))
        muteButton.tap()
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

        XCTAssertTrue(app.descendants(matching: .any)["liveTransmitPipelineView"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Mic"].exists)
        XCTAssertTrue(app.staticTexts["VAD"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["realDeviceCallDebugSummaryLabel"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["audioIOPanel"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["audioCheckPanel"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["callAudioOutputPicker"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["callAudioInputPicker"].exists)
    }

    @MainActor
    func testAudioCheckControlsAreAvailableFromSettings() throws {
        openSettingsTab()

        XCTAssertTrue(app.buttons["Record 5s and Play"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Microphone Input"].exists)
        XCTAssertTrue(app.staticTexts["Speaker Output"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["audioCheckPanel"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["audioIOPanel"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["transmitCodecPanel"].exists)
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

        XCTAssertTrue(app.descendants(matching: .any)["liveTransmitPipelineView"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Mic"].exists)
        XCTAssertTrue(app.staticTexts["VAD"].exists)
    }

    private func createTrailGroupAndOpenCall() {
        openGroupsTab()
        let createButton = app.buttons["createGroupButton"].firstMatch.exists
            ? app.buttons["createGroupButton"].firstMatch
            : app.buttons["Create Trail Group"].firstMatch
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
        if app.staticTexts["Recent Groups"].firstMatch.exists {
            return
        }
        if app.buttons["showGroupsButton"].firstMatch.exists {
            app.buttons["showGroupsButton"].firstMatch.tap()
            return
        }
        if app.tabBars.buttons["Groups"].firstMatch.exists {
            app.tabBars.buttons["Groups"].firstMatch.tap()
            return
        }
        if app.radioButtons["groupsTab"].firstMatch.exists {
            app.radioButtons["groupsTab"].firstMatch.tap()
            return
        }
        if app.buttons["Groups"].firstMatch.exists {
            app.buttons["Groups"].firstMatch.tap()
        }
    }

    private func openDiagnosticsTab() {
        if app.descendants(matching: .any)["liveTransmitPipelineView"].firstMatch.exists {
            return
        }
        if app.tabBars.buttons["Diagnostics"].firstMatch.exists {
            app.tabBars.buttons["Diagnostics"].firstMatch.tap()
            return
        }
        if app.radioButtons["diagnosticsTab"].firstMatch.exists {
            app.radioButtons["diagnosticsTab"].firstMatch.tap()
            return
        }
        if app.buttons["diagnosticsTab"].firstMatch.exists {
            app.buttons["diagnosticsTab"].firstMatch.tap()
            return
        }
        if app.buttons["Diagnostics"].firstMatch.exists {
            app.buttons["Diagnostics"].firstMatch.tap()
        }
    }

    private func openSettingsTab() {
        if app.descendants(matching: .any)["settingsScrollView"].firstMatch.exists {
            return
        }
        if app.tabBars.buttons["Settings"].firstMatch.exists {
            app.tabBars.buttons["Settings"].firstMatch.tap()
            return
        }
        if app.radioButtons["settingsTab"].firstMatch.exists {
            app.radioButtons["settingsTab"].firstMatch.tap()
            return
        }
        if app.buttons["settingsTab"].firstMatch.exists {
            app.buttons["settingsTab"].firstMatch.tap()
            return
        }
        if app.buttons["Settings"].firstMatch.exists {
            app.buttons["Settings"].firstMatch.tap()
        }
    }

    private func waitForVisibleRoot(in app: XCUIApplication) -> Bool {
        app.buttons["createGroupButton"].firstMatch.waitForExistence(timeout: 2)
            || app.buttons["Create Trail Group"].firstMatch.waitForExistence(timeout: 2)
            || app.descendants(matching: .any)["liveTransmitPipelineView"].firstMatch.waitForExistence(timeout: 2)
            || app.descendants(matching: .any)["settingsScrollView"].firstMatch.waitForExistence(timeout: 2)
            || app.buttons["diagnosticsTab"].firstMatch.waitForExistence(timeout: 2)
            || app.buttons["Diagnostics"].firstMatch.waitForExistence(timeout: 2)
            || app.radioButtons["diagnosticsTab"].firstMatch.waitForExistence(timeout: 2)
            || app.radioButtons["settingsTab"].firstMatch.waitForExistence(timeout: 2)
            || app.tabBars.buttons["Diagnostics"].firstMatch.waitForExistence(timeout: 2)
            || app.tabBars.buttons["Settings"].firstMatch.waitForExistence(timeout: 2)
    }
}
