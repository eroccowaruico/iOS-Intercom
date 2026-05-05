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

    @Test func appSourcesDoNotContainTestOnlyLaunchSwitches() throws {
        for sourcePath in try Self.appSwiftSourcePaths() {
            let source = try Self.source(sourcePath)
            #expect(source.contains("UI-TEST") == false)
            #expect(source.contains("isUITestProcess") == false)
            #expect(source.contains("ProcessInfo.processInfo.arguments") == false)
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

    @Test func encodedVoicePacketUsesPackagePCMCodecRoundTrip() throws {
        let samples: [Float] = [-1.0, -0.25, 0.0, 0.25, 1.0]
        let packet = try EncodedVoicePacket.make(frameID: 7, samples: samples)
        let decoded = try packet.decodeSamples()

        #expect(packet.frameID == 7)
        #expect(packet.codec == .pcm16)
        #expect(Self.maxAbsoluteDifference(samples, decoded) < 0.0001)
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

    @Test func jitterBufferDeliversReadyVoiceFramesInSequenceOrderAndDropsDuplicates() throws {
        let groupID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let streamID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        var buffer = JitterBuffer(playoutDelay: 0.08, packetLifetime: 1.0)
        let first = Self.receivedPacket(
            peerID: "peer-a",
            groupID: groupID,
            streamID: streamID,
            sequenceNumber: 1,
            sentAt: 10.00,
            frameID: 1,
            samples: [0.1]
        )
        let second = Self.receivedPacket(
            peerID: "peer-a",
            groupID: groupID,
            streamID: streamID,
            sequenceNumber: 2,
            sentAt: 10.02,
            frameID: 2,
            samples: [0.2]
        )

        buffer.enqueue(second, receivedAt: 10.02)
        buffer.enqueue(first, receivedAt: 10.00)
        buffer.enqueue(first, receivedAt: 10.00)

        let frames = buffer.drainReadyFrames(now: 10.10)

        #expect(frames.map(\.frameID) == [1, 2])
        #expect(frames.map(\.samples) == [[0.1], [0.2]])
        #expect(buffer.droppedFrameCount == 1)
        #expect(buffer.queuedFrameCount == 0)
    }

    @Test func audioFrameMixerSumsAndClampsSamples() {
        let frames = [
            JitterBufferedAudioFrame(peerID: "a", streamID: UUID(), sequenceNumber: 1, frameID: 1, samples: [0.6, -0.6]),
            JitterBufferedAudioFrame(peerID: "b", streamID: UUID(), sequenceNumber: 1, frameID: 1, samples: [0.7, -0.7])
        ]

        #expect(AudioFrameMixer.mix(frames) == [1.0, -1.0])
    }

    @Test func audioSessionManagerAppliesIntercomAndAudioCheckConfigurations() throws {
        let session = NoOpAudioSession()
        let manager = AudioSessionManager(session: session)

        try manager.configureForIntercom()
        try manager.deactivate()
        try manager.configureForAudioCheck()

        #expect(session.appliedConfigurations.count == 2)
        #expect(session.activeValues == [true, false, true])
        #expect(session.appliedConfigurations[0].mode == .default)
        #expect(session.appliedConfigurations[1].mode == .default)
    }

    @Test func systemAudioInputMonitorRequestsMicrophonePermissionBeforeStartingCapture() {
        let permission = FakeMicrophonePermissionAuthorizer(state: .notDetermined)
        let monitor = SystemAudioInputMonitor(microphonePermission: permission)

        #expect(throws: AudioInputMonitorError.microphonePermissionRequestPending) {
            try monitor.start()
        }
        #expect(permission.requestAccessCallCount == 1)
    }

    @Test func systemAudioInputMonitorFailsFastWhenMicrophonePermissionIsDenied() {
        let permission = FakeMicrophonePermissionAuthorizer(state: .denied)
        let monitor = SystemAudioInputMonitor(microphonePermission: permission)

        #expect(throws: AudioInputMonitorError.microphonePermissionDenied) {
            try monitor.start()
        }
        #expect(permission.requestAccessCallCount == 0)
    }

    @Test func viewModelCreatesAndPersistsTalkGroupWithoutTestMode() {
        let callSession = RecordingCallSession()
        let groupStore = InMemoryGroupStore()
        let viewModel = Self.makeViewModel(groups: [], callSession: callSession, groupStore: groupStore)

        viewModel.createTalkGroup()

        #expect(viewModel.groups.count == 1)
        #expect(viewModel.selectedGroup?.name == "Talk Group")
        #expect(viewModel.activeGroupID == viewModel.selectedGroup?.id)
        #expect(callSession.connectedGroup?.id == viewModel.selectedGroup?.id)
        #expect(groupStore.loadGroups().map(\.name) == ["Talk Group"])
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
        let viewModel = Self.makeViewModel(groups: [], credentialStore: credentialStore)

        try viewModel.acceptInviteURL(url, now: 150)

        #expect(viewModel.selectedGroup?.id == groupID)
        #expect(viewModel.inviteStatusMessage == "JOINED Invited Group")
        #expect(credentialStore.credential(for: groupID)?.secret == "shared-secret")
    }

    @Test func viewModelConnectsAuthenticatedPeerAndStartsAudioPipeline() async throws {
        let callSession = RecordingCallSession()
        let audioSession = NoOpAudioSession()
        let inputMonitor = NoOpAudioInputMonitor()
        let audioPlayer = NoOpAudioFramePlayer()
        let viewModel = Self.makeViewModel(
            callSession: callSession,
            audioSession: audioSession,
            audioInputMonitor: inputMonitor,
            audioFramePlayer: audioPlayer
        )

        let group = IntercomSeedData.recentGroups[0]
        viewModel.selectGroup(group)
        await Self.waitUntil { callSession.connectedGroup?.id == group.id }
        callSession.authenticate(["member-108"])
        await Self.waitUntil { viewModel.isAudioReady }

        #expect(callSession.startMediaCallCount == 1)
        #expect(inputMonitor.startCallCount == 1)
        #expect(audioPlayer.startCallCount == 1)
        #expect(audioSession.activeValues.contains(true))
        #expect(viewModel.connectionState == .localConnected)
    }

    @Test func viewModelDoesNotSwitchActiveGroupSelectionUntilDisconnect() {
        let callSession = RecordingCallSession()
        let viewModel = Self.makeViewModel(callSession: callSession)
        let firstGroup = IntercomSeedData.recentGroups[0]
        let secondGroup = IntercomSeedData.recentGroups[1]

        viewModel.selectGroup(firstGroup)
        viewModel.selectGroup(secondGroup)

        #expect(viewModel.selectedGroup?.id == secondGroup.id)
        #expect(viewModel.activeGroupID == firstGroup.id)
        #expect(callSession.connectedGroup?.id == firstGroup.id)
        #expect(callSession.disconnectCallCount == 0)

        viewModel.disconnect()
        viewModel.connectLocal()

        #expect(viewModel.activeGroupID == secondGroup.id)
        #expect(callSession.connectedGroup?.id == secondGroup.id)
    }

    @Test func viewModelSendsVoiceSamplesFromMicrophoneFrames() async throws {
        let callSession = RecordingCallSession()
        let inputMonitor = NoOpAudioInputMonitor()
        let viewModel = Self.makeViewModel(callSession: callSession, audioInputMonitor: inputMonitor)

        viewModel.selectGroup(IntercomSeedData.recentGroups[0])
        callSession.authenticate(["member-108"])
        await Self.waitUntil { viewModel.isAudioReady }
        inputMonitor.simulate(samples: [0.3])
        inputMonitor.simulate(samples: [0.4])
        await Self.waitUntil { callSession.sentAudioPackets.count >= 2 }

        #expect(callSession.sentAudioPackets.prefix(2) == [
            .voice(frameID: 1, samples: [0.3]),
            .voice(frameID: 2, samples: [0.4])
        ])
    }

    @Test func viewModelReceivesRemoteAudioUpdatesMemberAndPlaybackDiagnostics() async throws {
        let callSession = RecordingCallSession()
        let ticker = NoOpCallTicker()
        let audioPlayer = NoOpAudioFramePlayer()
        let viewModel = Self.makeViewModel(
            callSession: callSession,
            callTicker: ticker,
            audioFramePlayer: audioPlayer
        )
        let group = IntercomSeedData.recentGroups[0]
        let packet = Self.receivedPacket(
            peerID: "member-108",
            groupID: group.id,
            streamID: UUID(),
            sequenceNumber: 1,
            sentAt: 100,
            frameID: 1,
            samples: [0.2, -0.2]
        )

        viewModel.selectGroup(group)
        callSession.authenticate(["member-108"])
        await Self.waitUntil { viewModel.isAudioReady }
        callSession.receive(packet)
        await Self.waitUntil { viewModel.receivedVoicePacketCount == 1 }
        ticker.simulateTick(now: 100.1)
        await Self.waitUntil { audioPlayer.playedFrames.count == 1 }

        let remoteMember = try #require(viewModel.selectedGroup?.members.first { $0.id == "member-108" })
        #expect(remoteMember.isTalking)
        #expect(remoteMember.receivedAudioPacketCount == 1)
        #expect(viewModel.playedAudioFrameCount == 1)
        #expect(audioPlayer.playedFrames[0].samples == [0.2, -0.2])
    }

    @Test func viewModelBroadcastsMuteStateAsControlMessage() async throws {
        let callSession = RecordingCallSession()
        let inputMonitor = NoOpAudioInputMonitor()
        let viewModel = Self.makeViewModel(callSession: callSession, audioInputMonitor: inputMonitor)

        viewModel.selectGroup(IntercomSeedData.recentGroups[0])
        callSession.authenticate(["member-108"])
        await Self.waitUntil { viewModel.isAudioReady }
        viewModel.toggleMute()

        #expect(inputMonitor.lastInputMuted == true)
        #expect(callSession.sentControlMessages.contains(.peerMuteState(isMuted: true)))
        #expect(callSession.sentControlMessages.contains(.keepalive))
    }

    @Test func viewModelAudioCheckRecordsAndPlaysBackSamples() async {
        let inputMonitor = NoOpAudioInputMonitor()
        let audioPlayer = NoOpAudioFramePlayer()
        let viewModel = Self.makeViewModel(
            groups: [],
            audioInputMonitor: inputMonitor,
            audioFramePlayer: audioPlayer
        )

        viewModel.startAudioCheck(recordDuration: .milliseconds(20), playbackDuration: .seconds(5))
        inputMonitor.simulate(samples: [0.5, -0.5])
        await Self.waitUntil { viewModel.audioCheckInputLevel > 0 }
        await Self.waitUntil { viewModel.audioCheckPhase == .playing }

        #expect(viewModel.audioCheckPhase == .playing)
        #expect(viewModel.audioCheckInputLevel > 0)
        #expect(viewModel.audioCheckOutputLevel > 0)
        #expect(audioPlayer.playedFrames.count == 1)
    }

    @Test func viewModelResetAllSettingsKeepsGroupsAndRestoresAudioDefaults() {
        let viewModel = Self.makeViewModel()

        viewModel.setVoiceActivityDetectionThreshold(VoiceActivityDetector.maxThreshold)
        viewModel.setMasterOutputVolume(IntercomViewModel.maximumMasterOutputVolume)
        viewModel.toggleOutputMute()
        viewModel.setRemoteOutputVolume(peerID: "member-108", value: 0.2)
        viewModel.resetAllSettings()

        #expect(viewModel.voiceActivityDetectionThreshold == AudioTransmissionController.defaultVoiceActivityThreshold)
        #expect(viewModel.masterOutputVolume == IntercomViewModel.normalMasterOutputVolume)
        #expect(!viewModel.isOutputMuted)
        #expect(viewModel.remoteOutputVolumes.isEmpty)
        #expect(viewModel.groups.count == IntercomSeedData.recentGroups.count)
    }

    @Test func diagnosticsSnapshotSummarizesCurrentAppState() {
        let viewModel = Self.makeViewModel()
        let snapshot = viewModel.diagnosticsSnapshot

        #expect(snapshot.transportSummary == "TRANSPORT RecordingCallSession")
        #expect(snapshot.audio.summary.contains("TX 0"))
        #expect(snapshot.connectionSummary == "PEERS 0")
        #expect(snapshot.codecSafetySummary == "TX FB #0")
    }

    private static func makeViewModel(
        groups: [IntercomGroup] = IntercomSeedData.recentGroups,
        callSession: RecordingCallSession = RecordingCallSession(),
        credentialStore: GroupCredentialStoring = InMemoryGroupCredentialStore(),
        groupStore: GroupStoring? = nil,
        localMemberIdentityStore: LocalMemberIdentityStoring? = nil,
        audioSession: NoOpAudioSession = NoOpAudioSession(),
        audioInputMonitor: AudioInputMonitoring = NoOpAudioInputMonitor(),
        callTicker: CallTicking = NoOpCallTicker(),
        audioFramePlayer: AudioFramePlaying = NoOpAudioFramePlayer()
    ) -> IntercomViewModel {
        let identityStore = localMemberIdentityStore ?? InMemoryLocalMemberIdentityStore(
            identity: LocalMemberIdentity(memberID: groups.first?.members.first?.id ?? "member-local", displayName: "You")
        )
        return IntercomViewModel(
            groups: groups,
            callSession: callSession,
            credentialStore: credentialStore,
            groupStore: groupStore ?? InMemoryGroupStore(groups: groups),
            localMemberIdentityStore: identityStore,
            audioSessionManager: AudioSessionManager(session: audioSession),
            audioInputMonitor: audioInputMonitor,
            callTicker: callTicker,
            audioFramePlayer: audioFramePlayer
        )
    }

    private static func receivedPacket(
        peerID: String,
        groupID: UUID,
        streamID: UUID,
        sequenceNumber: Int,
        sentAt: TimeInterval,
        frameID: Int,
        samples: [Float]
    ) -> ReceivedAudioPacket {
        let envelope = AudioPacketEnvelope(
            groupID: groupID,
            streamID: streamID,
            sequenceNumber: sequenceNumber,
            sentAt: sentAt,
            packet: .voice(frameID: frameID, samples: samples)
        )
        return ReceivedAudioPacket(
            peerID: peerID,
            envelope: envelope,
            packet: .voice(frameID: frameID, samples: samples)
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

    private static func maxAbsoluteDifference(_ lhs: [Float], _ rhs: [Float]) -> Float {
        zip(lhs, rhs)
            .map { abs($0 - $1) }
            .max() ?? 0
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
    private(set) var sentAudioPackets: [OutboundAudioPacket] = []
    private(set) var sentControlMessages: [ControlMessage] = []
    private(set) var sentApplicationDataMessages: [ApplicationDataMessage] = []

    func startStandby(group: IntercomGroup) {
        connectedGroup = group
        onEvent?(.localNetworkStatus(LocalNetworkEvent(status: .advertisingBrowsing)))
    }

    func connect(group: IntercomGroup) {
        connectedGroup = group
        let peerIDs = group.members.map(\.id)
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

    func sendAudioFrame(_ frame: OutboundAudioPacket) {
        sentAudioPackets.append(frame)
        guard case .voice = frame else { return }
        onEvent?(.outboundPacketBuilt(OutboundPacketDiagnostics(
            route: .local,
            streamID: UUID(),
            sequenceNumber: sentAudioPackets.count,
            packetKind: .voice,
            metadata: nil
        )))
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

    func receive(_ packet: ReceivedAudioPacket) {
        onEvent?(.receivedPacket(packet))
    }
}

private final class NoOpAudioSession: AudioSessionApplying {
    private(set) var appliedConfigurations: [AudioSessionConfiguration] = []
    private(set) var activeValues: [Bool] = []

    func apply(_ configuration: AudioSessionConfiguration) throws {
        appliedConfigurations.append(configuration)
    }

    func setActive(_ active: Bool) throws {
        activeValues.append(active)
    }
}

private final class NoOpAudioInputMonitor: AudioInputMonitoring {
    var onLevel: ((Float) -> Void)?
    var onSamples: (([Float]) -> Void)?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var lastInputMuted = false

    func start() throws {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func setInputMuted(_ muted: Bool) {
        lastInputMuted = muted
    }

    func simulate(level: Float) {
        onLevel?(level)
    }

    func simulate(samples: [Float]) {
        onSamples?(samples)
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

    func simulateTick(now: TimeInterval) {
        guard isRunning else { return }
        onTick?(now)
    }
}

private final class NoOpAudioFramePlayer: AudioFramePlaying {
    private(set) var playedFrames: [JitterBufferedAudioFrame] = []
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start() throws {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func play(_ frame: JitterBufferedAudioFrame) {
        playedFrames.append(frame)
    }

    func play(_ frames: [JitterBufferedAudioFrame]) {
        playedFrames.append(contentsOf: frames)
    }
}

private final class FakeMicrophonePermissionAuthorizer: MicrophonePermissionAuthorizing {
    private let state: MicrophoneAuthorizationState
    private(set) var requestAccessCallCount = 0

    init(state: MicrophoneAuthorizationState) {
        self.state = state
    }

    func authorizationState() -> MicrophoneAuthorizationState {
        state
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        requestAccessCallCount += 1
    }
}
