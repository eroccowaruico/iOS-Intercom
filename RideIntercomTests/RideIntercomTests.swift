import Foundation
import RTC
import SessionManager
import Testing
@testable import RideIntercom

@MainActor
struct RideIntercomTests {
    @Test func appTargetSupportsIOSAndMacOSWithoutAudioUnitLinkage() throws {
        let project = try Self.source("RideIntercom.xcodeproj/project.pbxproj")

        #expect(project.contains("iphoneos iphonesimulator macosx"))
        #expect(project.contains("AudioUnit.framework in Frameworks") == false)
    }

    @Test func appSourcesDoNotContainTestOnlyLaunchSwitchesOrObsoleteAudioPipeline() throws {
        let obsoleteTerms = [
            "UI-TEST",
            "isUITestProcess",
            "ProcessInfo.processInfo.arguments",
            "SystemAudioInputMonitor",
            "SystemAudioOutputRenderer",
            "SystemAudioSessionAdapter",
            "JitterBuffer",
            "AudioFrameMixer",
            "AudioPacketEnvelope",
            "ReceivedAudioPacket",
            "streamID"
        ]
        for sourcePath in try Self.appSwiftSourcePaths() {
            let source = try Self.source(sourcePath)
            for term in obsoleteTerms {
                #expect(source.contains(term) == false, "\(sourcePath) contains \(term)")
            }
        }
    }

    @Test func uiSourcesAreSplitByScreenResponsibility() throws {
        let contentView = try Self.source("RideIntercom/UI/ContentView.swift")
        let callView = try Self.source("RideIntercom/UI/Call/CallView.swift")
        let settingsView = try Self.source("RideIntercom/UI/Settings/SettingsView.swift")
        let diagnosticsView = try Self.source("RideIntercom/UI/Diagnostics/DiagnosticsView.swift")

        #expect(contentView.contains("struct ContentView"))
        #expect(contentView.components(separatedBy: .newlines).count < 80)
        #expect(callView.contains("struct CallView"))
        #expect(settingsView.contains("struct SettingsView"))
        #expect(diagnosticsView.contains("struct DiagnosticsView"))
    }

    @Test func appRootKeepsPlatformSpecificWindowPolicyAtMacBoundary() throws {
        let appSource = try Self.source("RideIntercom/App/RideIntercomApp.swift")
        let windowPolicySource = try Self.source("RideIntercom/App/SingleWindowPolicy.swift")

        #expect(appSource.contains("WindowGroup(id: SingleWindowPolicy.mainWindowID)"))
        #expect(appSource.contains("WindowGroup {"))
        #expect(appSource.contains("#if os(macOS)"))
        #expect(windowPolicySource.contains("#if os(macOS)"))
        #expect(windowPolicySource.contains("applicationShouldTerminateAfterLastWindowClosed"))
        #expect(windowPolicySource.contains("applicationShouldSaveApplicationState"))
        #expect(windowPolicySource.contains("applicationShouldRestoreApplicationState"))
    }

    @Test func appInfoPlistEnablesBackgroundAudioMode() throws {
        let plistURL = Self.workspaceRoot().appendingPathComponent("RideIntercom/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        )
        let backgroundModes = try #require(plist["UIBackgroundModes"] as? [String])

        #expect(backgroundModes.contains("audio"))
    }

    @Test func currentProcessUsesPackageBackedRTCRouteManager() {
        let viewModel = IntercomViewModel.makeForCurrentProcess()

        #expect(viewModel.callSessionDebugTypeName == "RTC RouteManager")
        #expect(viewModel.transportDebugSummary == "TRANSPORT RTC RouteManager")
    }

    @Test func groupInviteTokenRoundTripsAndRejectsTampering() throws {
        let groupID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let token = try GroupInviteToken.make(
            groupID: groupID,
            groupName: "Talk Group",
            groupSecret: "talk-secret",
            inviterMemberID: "member-001",
            issuedAt: 100,
            expiresAt: 200
        )

        let url = try GroupInviteTokenCodec.joinURL(for: token)
        let decoded = try GroupInviteTokenCodec.decodeJoinURL(url)
        let tampered = try GroupInviteToken(
            version: decoded.version,
            groupID: decoded.groupID,
            groupName: "Other Group",
            groupSecret: decoded.groupSecret,
            inviterMemberID: decoded.inviterMemberID,
            issuedAt: decoded.issuedAt,
            expiresAt: decoded.expiresAt,
            signature: decoded.signature
        )

        #expect(url.absoluteString.hasPrefix("rideintercom://join?token="))
        #expect(decoded == token)
        #expect(decoded.verifySignature())
        #expect(!tampered.verifySignature())
        #expect(!token.isExpired(now: 199.9))
        #expect(token.isExpired(now: 200))
    }

    @Test func audioTransmissionControllerSendsVoiceAndKeepalive() {
        var controller = AudioTransmissionController(
            detector: VoiceActivityDetector(threshold: 0.1),
            preRollLimit: 2,
            keepaliveIntervalFrames: 3
        )

        #expect(controller.process(frameID: 1, level: 0, samples: [0.0]).isEmpty)
        #expect(controller.process(frameID: 2, level: 0, samples: [0.0]).isEmpty)
        #expect(controller.process(frameID: 3, level: 0, samples: [0.0]) == [.keepalive])

        let voicePackets = controller.process(frameID: 4, level: 0.3, samples: [0.3])
        #expect(voicePackets == [
            .voice(frameID: 2, samples: [0.0]),
            .voice(frameID: 3, samples: [0.0]),
            .voice(frameID: 4, samples: [0.3])
        ])
    }

    @Test func viewModelCreatesAndPersistsTalkGroupWithoutTestMode() {
        let harness = Self.makeHarness(groups: [])

        harness.viewModel.createTalkGroup()

        #expect(harness.viewModel.groups.count == 1)
        #expect(harness.viewModel.selectedGroup?.name == "Talk Group")
        #expect(harness.viewModel.activeGroupID == harness.viewModel.selectedGroup?.id)
        #expect(harness.callSession.connectedGroup?.id == harness.viewModel.selectedGroup?.id)
        #expect(harness.groupStore.loadGroups().map(\.name) == ["Talk Group"])
    }

    @Test func viewModelAcceptsInviteURLAndStoresCredential() throws {
        let credentialStore = InMemoryGroupCredentialStore()
        let groupID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let token = try GroupInviteToken.make(
            groupID: groupID,
            groupName: "Invited Group",
            groupSecret: "shared-secret",
            inviterMemberID: "member-remote",
            issuedAt: 100,
            expiresAt: 200
        )
        let url = try GroupInviteTokenCodec.joinURL(for: token)
        let harness = Self.makeHarness(groups: [], credentialStore: credentialStore)

        try harness.viewModel.acceptInviteURL(url, now: 150)

        #expect(harness.viewModel.selectedGroup?.id == groupID)
        #expect(harness.viewModel.inviteStatusMessage == "JOINED Invited Group")
        #expect(credentialStore.credential(for: groupID)?.secret == "shared-secret")
    }

    @Test func viewModelConnectsAuthenticatedPeerAndStartsPackageAudioPipeline() async throws {
        let harness = Self.makeHarness()
        let group = IntercomSeedData.recentGroups[0]

        harness.viewModel.selectGroup(group)
        await Self.waitUntil { harness.callSession.connectedGroup?.id == group.id }
        harness.callSession.authenticate(["member-108"])
        await Self.waitUntil { harness.viewModel.isAudioReady }

        #expect(harness.callSession.startMediaCallCount == 1)
        #expect(harness.audioSessionBackend.activeValues.contains(true))
        #expect(harness.inputBackend.startCount == 1)
        #expect(harness.outputBackend.startCount == 1)
        #expect(harness.viewModel.connectionState == .localConnected)
    }

    @Test func viewModelSendsVoiceSamplesFromPackageInputFrames() async throws {
        let harness = Self.makeHarness()

        harness.viewModel.selectGroup(IntercomSeedData.recentGroups[0])
        harness.callSession.authenticate(["member-108"])
        await Self.waitUntil { harness.viewModel.isAudioReady }
        harness.inputBackend.emit(AudioStreamFrame(sequenceNumber: 1, format: .intercom, capturedAt: 100, samples: [0.3]))
        harness.inputBackend.emit(AudioStreamFrame(sequenceNumber: 2, format: .intercom, capturedAt: 101, samples: [0.4]))
        await Self.waitUntil { harness.callSession.sentAudioPackets.count >= 2 }

        #expect(harness.callSession.sentAudioPackets.prefix(2) == [
            .voice(frameID: 1, samples: [0.3]),
            .voice(frameID: 2, samples: [0.4])
        ])
    }

    @Test func viewModelReceivesRTCFrameAndSchedulesPackageOutput() async throws {
        let harness = Self.makeHarness()
        let group = IntercomSeedData.recentGroups[0]
        let frame = RTC.AudioFrame(
            sequenceNumber: 7,
            format: .intercomPacketAudio,
            capturedAt: 100,
            samples: [0.2, -0.2]
        )

        harness.viewModel.selectGroup(group)
        harness.callSession.authenticate(["member-108"])
        await Self.waitUntil { harness.viewModel.isAudioReady }
        harness.callSession.receive(RTC.ReceivedAudioFrame(peerID: RTC.PeerID(rawValue: "member-108"), frame: frame))
        await Self.waitUntil { harness.outputBackend.scheduledFrames.count == 1 }

        let remoteMember = try #require(harness.viewModel.selectedGroup?.members.first { $0.id == "member-108" })
        #expect(remoteMember.isTalking)
        #expect(remoteMember.receivedAudioPacketCount == 1)
        #expect(remoteMember.playedAudioFrameCount == 1)
        #expect(harness.viewModel.playedAudioFrameCount == 1)
        #expect(harness.outputBackend.scheduledFrames[0].sequenceNumber == 7)
        #expect(harness.outputBackend.scheduledFrames[0].samples == [0.2, -0.2])
    }

    @Test func viewModelUsesRTCMetricsForReceiveBufferDiagnostics() async {
        let harness = Self.makeHarness()

        harness.callSession.publishMetrics(RTC.RouteMetrics(
            route: .multipeer,
            activePeerCount: 1,
            receivedAudioFrameCount: 5,
            droppedAudioFrameCount: 2,
            queuedAudioFrameCount: 3
        ))
        await Self.waitUntil { harness.viewModel.jitterQueuedFrameCount == 3 }

        #expect(harness.viewModel.receivedVoicePacketCount == 5)
        #expect(harness.viewModel.droppedAudioPacketCount == 2)
        #expect(harness.viewModel.jitterQueuedFrameCount == 3)
    }

    @Test func viewModelBroadcastsMuteStateAndUpdatesPackageVoiceProcessing() async throws {
        let harness = Self.makeHarness()

        harness.viewModel.selectGroup(IntercomSeedData.recentGroups[0])
        harness.callSession.authenticate(["member-108"])
        await Self.waitUntil { harness.viewModel.isAudioReady }
        harness.viewModel.toggleMute()

        #expect(harness.voiceProcessingBackend.mutedValues.last == true)
        #expect(harness.callSession.localMuteValues.last == true)
        #expect(harness.callSession.sentControlMessages.contains(.peerMuteState(isMuted: true)))
        #expect(harness.callSession.sentControlMessages.contains(.keepalive))
    }

    @Test func viewModelAudioCheckRecordsAndSchedulesPlaybackThroughPackageOutput() async {
        let harness = Self.makeHarness(groups: [])

        harness.viewModel.startAudioCheck(recordDuration: .milliseconds(20), playbackDuration: .seconds(5))
        harness.inputBackend.emit(AudioStreamFrame(sequenceNumber: 1, format: .intercom, capturedAt: 100, samples: [0.5, -0.5]))
        await Self.waitUntil { harness.viewModel.audioCheckInputLevel > 0 }
        await Self.waitUntil { harness.viewModel.audioCheckPhase == .playing }

        #expect(harness.viewModel.audioCheckPhase == .playing)
        #expect(harness.viewModel.audioCheckInputLevel > 0)
        #expect(harness.viewModel.audioCheckOutputLevel > 0)
        #expect(harness.outputBackend.scheduledFrames.count == 1)
        #expect(harness.outputBackend.scheduledFrames[0].samples == [0.5, -0.5])
    }

    @Test func viewModelResetAllSettingsKeepsGroupsAndRestoresAudioDefaults() {
        let harness = Self.makeHarness()

        harness.viewModel.setVoiceActivityDetectionThreshold(VoiceActivityDetector.maxThreshold)
        harness.viewModel.toggleOutputMute()
        harness.viewModel.resetAllSettings()

        #expect(harness.viewModel.voiceActivityDetectionThreshold == AudioTransmissionController.defaultVoiceActivityThreshold)
        #expect(!harness.viewModel.isOutputMuted)
        #expect(harness.viewModel.groups.count == IntercomSeedData.recentGroups.count)
        #expect(harness.callSession.outputMuteValues.last == false)
    }

    @Test func diagnosticsSnapshotSummarizesCurrentAppState() {
        let harness = Self.makeHarness()
        let snapshot = harness.viewModel.diagnosticsSnapshot

        #expect(snapshot.transportSummary == "TRANSPORT RecordingCallSession")
        #expect(snapshot.audio.summary.contains("TX 0"))
        #expect(snapshot.connectionSummary == "PEERS 0")
    }

    private struct Harness {
        let viewModel: IntercomViewModel
        let callSession: RecordingCallSession
        let groupStore: InMemoryGroupStore
        let audioSessionBackend: FakeAudioSessionBackend
        let inputBackend: FakeInputStreamBackend
        let outputBackend: FakeOutputStreamBackend
        let voiceProcessingBackend: FakeVoiceProcessingBackend
    }

    private static func makeHarness(
        groups: [IntercomGroup]? = nil,
        credentialStore: GroupCredentialStoring? = nil
    ) -> Harness {
        let groups = groups ?? IntercomSeedData.recentGroups
        let credentialStore = credentialStore ?? InMemoryGroupCredentialStore()
        let callSession = RecordingCallSession()
        let groupStore = InMemoryGroupStore(groups: groups)
        let audioSessionBackend = FakeAudioSessionBackend()
        let inputBackend = FakeInputStreamBackend()
        let outputBackend = FakeOutputStreamBackend()
        let voiceProcessingBackend = FakeVoiceProcessingBackend()
        let voiceProcessingManager = AudioInputVoiceProcessingManager(backend: voiceProcessingBackend)
        let identityStore = InMemoryLocalMemberIdentityStore(
            identity: LocalMemberIdentity(memberID: groups.first?.members.first?.id ?? "member-local", displayName: "You")
        )
        let viewModel = IntercomViewModel(
            groups: groups,
            callSession: callSession,
            credentialStore: credentialStore,
            groupStore: groupStore,
            localMemberIdentityStore: identityStore,
            audioSessionManager: AudioSessionManager(backend: audioSessionBackend),
            audioInputCapture: AudioInputStreamCapture(
                configuration: .intercom(voiceProcessing: IntercomViewModel.defaultVoiceProcessingConfiguration()),
                backend: inputBackend
            ),
            audioOutputRenderer: AudioOutputStreamRenderer(configuration: .intercom, backend: outputBackend),
            audioInputVoiceProcessingManager: voiceProcessingManager,
            callTicker: NoOpCallTicker()
        )
        return Harness(
            viewModel: viewModel,
            callSession: callSession,
            groupStore: groupStore,
            audioSessionBackend: audioSessionBackend,
            inputBackend: inputBackend,
            outputBackend: outputBackend,
            voiceProcessingBackend: voiceProcessingBackend
        )
    }

    private static func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let start = ContinuousClock.now
        while !condition(), start.duration(to: .now) < timeout {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func workspaceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func source(_ relativePath: String) throws -> String {
        let fileURL = workspaceRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private static func appSwiftSourcePaths() throws -> [String] {
        let appURL = workspaceRoot().appendingPathComponent("RideIntercom")
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: appURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )
        let urls = enumerator?.compactMap { $0 as? URL } ?? []
        return try urls.compactMap { url in
            if url.path.contains("/packages/") || url.pathExtension != "swift" {
                return nil
            }
            let values = try url.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { return nil }
            return url.path.replacingOccurrences(of: workspaceRoot().path + "/", with: "")
        }
    }
}

private final class RecordingCallSession: RideIntercom.CallSession {
    var onEvent: ((TransportEvent) -> Void)?
    private(set) var activeRouteDebugTypeName = "RecordingCallSession"
    private(set) var connectedGroup: IntercomGroup?
    private(set) var startMediaCallCount = 0
    private(set) var stopMediaCallCount = 0
    private(set) var disconnectCallCount = 0
    private(set) var preferredCodecs: [AudioCodecIdentifier] = []
    private(set) var localMuteValues: [Bool] = []
    private(set) var outputMuteValues: [Bool] = []
    private(set) var sentAudioPackets: [OutboundAudioPacket] = []
    private(set) var sentControlMessages: [ControlMessage] = []
    private(set) var sentApplicationDataMessages: [ApplicationDataMessage] = []

    func startStandby(group: IntercomGroup) {
        connectedGroup = group
        onEvent?(.localNetworkStatus(LocalNetworkEvent(status: .advertisingBrowsing)))
    }

    func connect(group: IntercomGroup) {
        connectedGroup = group
        let peerIDs = group.members.dropFirst().map(\.id)
        onEvent?(.localNetworkStatus(LocalNetworkEvent(status: .advertisingBrowsing)))
        onEvent?(.connected(peerIDs: peerIDs))
    }

    func startMedia() {
        startMediaCallCount += 1
    }

    func stopMedia() {
        stopMediaCallCount += 1
    }

    func disconnect() {
        disconnectCallCount += 1
        connectedGroup = nil
        onEvent?(.disconnected)
    }

    func setPreferredAudioCodec(_ codec: AudioCodecIdentifier) {
        preferredCodecs.append(codec)
    }

    func setLocalMute(_ muted: Bool) {
        localMuteValues.append(muted)
    }

    func setOutputMute(_ muted: Bool) {
        outputMuteValues.append(muted)
    }

    func sendAudioFrame(_ frame: OutboundAudioPacket) {
        sentAudioPackets.append(frame)
    }

    func sendControl(_ message: ControlMessage) {
        sentControlMessages.append(message)
    }

    func sendApplicationData(_ message: ApplicationDataMessage) {
        sentApplicationDataMessages.append(message)
    }

    func authenticate(_ peerIDs: [String]) {
        onEvent?(.authenticated(peerIDs: peerIDs))
    }

    func receive(_ frame: RTC.ReceivedAudioFrame) {
        onEvent?(.receivedAudioFrame(frame))
    }

    func publishMetrics(_ metrics: RTC.RouteMetrics) {
        onEvent?(.routeMetrics(metrics))
    }
}

private final class FakeAudioSessionBackend: SessionManager.AudioSessionBackend {
    private(set) var appliedConfigurations: [SessionManager.ResolvedAudioSessionConfiguration] = []
    private(set) var activeValues: [Bool] = []
    private var snapshotChangeHandler: SessionManager.AudioSessionSnapshotChangeHandler?
    var current = AudioSessionSnapshot(
        isActive: false,
        availableInputs: [
            .systemDefaultInput,
            AudioSessionDevice(id: "input-1", name: "Input 1", direction: .input)
        ],
        availableOutputs: [
            .systemDefaultOutput,
            .builtInSpeaker
        ],
        currentInput: .systemDefaultInput,
        currentOutput: .systemDefaultOutput
    )

    func apply(_ configuration: SessionManager.ResolvedAudioSessionConfiguration) throws {
        appliedConfigurations.append(configuration)
    }

    func setActive(_ active: Bool) throws {
        activeValues.append(active)
        current.isActive = active
    }

    func setPreferredInput(_ selection: SessionManager.AudioSessionDeviceSelection) throws {
        if selection == .systemDefault {
            current.currentInput = .systemDefaultInput
        }
    }

    func setPreferredOutput(_ selection: SessionManager.AudioSessionDeviceSelection) throws {
        if selection == .builtInSpeaker {
            current.currentOutput = .builtInSpeaker
        } else if selection == .systemDefault {
            current.currentOutput = .systemDefaultOutput
        }
    }

    func setPrefersEchoCancelledInput(_ enabled: Bool) throws {
        _ = enabled
    }

    func currentSnapshot() throws -> SessionManager.AudioSessionSnapshot {
        current
    }

    func setSnapshotChangeHandler(_ handler: SessionManager.AudioSessionSnapshotChangeHandler?) {
        snapshotChangeHandler = handler
    }
}

private final class FakeInputStreamBackend: SessionManager.AudioInputStreamBackend {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var onFrame: ((SessionManager.AudioStreamFrame) -> Void)?

    func startCapture(
        configuration: SessionManager.AudioInputStreamConfiguration,
        onFrame: @escaping (SessionManager.AudioStreamFrame) -> Void
    ) throws {
        _ = configuration
        startCount += 1
        self.onFrame = onFrame
    }

    func stopCapture() throws {
        stopCount += 1
        onFrame = nil
    }

    func emit(_ frame: SessionManager.AudioStreamFrame) {
        onFrame?(frame)
    }
}

private final class FakeOutputStreamBackend: SessionManager.AudioOutputStreamBackend {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var scheduledFrames: [SessionManager.AudioStreamFrame] = []

    func startRendering(configuration: SessionManager.AudioOutputStreamConfiguration) throws {
        _ = configuration
        startCount += 1
    }

    func stopRendering() throws {
        stopCount += 1
    }

    func schedule(_ frame: SessionManager.AudioStreamFrame) throws {
        scheduledFrames.append(frame)
    }
}

private final class FakeVoiceProcessingBackend: SessionManager.AudioInputVoiceProcessingBackend {
    private(set) var enabledValues: [Bool] = []
    private(set) var bypassedValues: [Bool] = []
    private(set) var duckingValues: [(enabled: Bool, level: SessionManager.AudioSessionDuckingLevel)] = []
    private(set) var mutedValues: [Bool] = []

    func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        enabledValues.append(enabled)
    }

    func setVoiceProcessingBypassed(_ bypassed: Bool) throws {
        bypassedValues.append(bypassed)
    }

    func setAdvancedDucking(enabled: Bool, level: SessionManager.AudioSessionDuckingLevel) throws {
        duckingValues.append((enabled, level))
    }

    func setInputMuted(_ muted: Bool) throws {
        mutedValues.append(muted)
    }
}

private final class NoOpCallTicker: CallTicking {
    var onTick: ((TimeInterval) -> Void)?
    private(set) var isRunning = false

    func start() {
        isRunning = true
    }

    func stop() {
        isRunning = false
    }
}
