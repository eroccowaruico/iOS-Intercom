import Foundation
import AudioMixer
import Codec
import RTC
import SessionManager
import Testing
import VADGate
@testable import RideIntercom

@MainActor
struct RideIntercomTests {
    @Test func appTargetSupportsIOSAndMacOSWithoutAudioUnitLinkage() throws {
        let project = try Self.source("RideIntercom.xcodeproj/project.pbxproj")

        #expect(project.contains("iphoneos iphonesimulator macosx"))
        #expect(project.contains("AudioUnit.framework in Frameworks") == false)
        #expect(project.contains("RTCNativeWebRTC"))
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
        let transmitPipelineView = try Self.source("RideIntercom/UI/Diagnostics/LiveTransmitPipelineView.swift")
        let receivePipelineView = try Self.source("RideIntercom/UI/Diagnostics/LiveReceivePipelineView.swift")
        let effectChainSource = try Self.source("RideIntercom/Intercom/ViewModel/IntercomViewModel+EffectChains.swift")
        let callSessionAdapter = try Self.source("RideIntercom/Intercom/Transport/CallSessionAdapter.swift")
        let diagnosticsSpec = try Self.source("docs/spec/App/UI/Diagnostics.md")
        let audioSpec = try Self.source("docs/spec/App/音声処理仕様.md")

        #expect(contentView.contains("struct ContentView"))
        #expect(contentView.components(separatedBy: .newlines).count < 80)
        #expect(callView.contains("struct CallView"))
        #expect(settingsView.contains("struct SettingsView"))
        #expect(settingsView.contains("struct CommunicationPanel"))
        #expect(settingsView.contains("localNetworkRouteToggle"))
        #expect(settingsView.contains("internetRouteToggle"))
        #expect(settingsView.contains("internetRouteToggle"))
        #expect(diagnosticsView.contains("struct DiagnosticsView"))
        #expect(callView.contains("masterVoiceIsolationToggle"))
        #expect(callView.contains("RemoteParticipantRowView"))
        let participantViews = try Self.source("RideIntercom/UI/Call/ParticipantViews.swift")
        #expect(participantViews.contains("participantOutputSlider"))
        #expect(participantViews.contains("participantVoiceIsolationToggle"))
        #expect(transmitPipelineView.contains("CompactEffectChainGroup"))
        #expect(transmitPipelineView.contains("ViewThatFits(in: .horizontal)"))
        #expect(transmitPipelineView.contains("minHeight: 104") == false)
        #expect(receivePipelineView.contains("ReceiveRTCPeersGroup"))
        #expect(receivePipelineView.contains("ReceiveDecodePeersGroup"))
        #expect(receivePipelineView.contains("ReceivePeerBusCompactRow"))
        #expect(receivePipelineView.contains("ReceivePeerBusCard") == false)
        #expect(receivePipelineView.contains("receiveCodecSummary") == false)
        #expect(transmitPipelineView.contains("viewModel.transmitEffectChainSnapshot"))
        #expect(receivePipelineView.contains("stageIdentifierPrefix: \"receive-master-effect-stage\""))
        #expect(receivePipelineView.contains("viewModel.receivePeerEffectChainSnapshot"))
        #expect(receivePipelineView.contains("viewModel.receiveMasterEffectChainSnapshot"))
        #expect(receivePipelineView.contains("connectionLabel(member.connectionState)"))
        #expect(receivePipelineView.contains("activeCodec: member.activeCodec"))
        #expect(transmitPipelineView.contains("viewModel.mixerBusSnapshot(id: \"tx-bus\")"))
        #expect(receivePipelineView.contains("viewModel.audioMixerSnapshot.routes.filter"))
        #expect(receivePipelineView.contains("receive-peer-rtc-\\(index)"))
        #expect(receivePipelineView.contains("receive-peer-codec-\\(index)"))
        #expect(receivePipelineView.contains("DEC \\(codecLabel(peer.activeCodec))"))
        #expect(receivePipelineView.contains("RTC \\(peerBus.connectionLabel)") == false)
        #expect(receivePipelineView.contains("DEC \\(codecLabel(peerBus.activeCodec))") == false)
        #expect(receivePipelineView.contains("ViewThatFits(in: .horizontal)"))
        #expect(receivePipelineView.contains("defaultReceiveSoundIsolationEnabled") == false)
        #expect(effectChainSource.contains("var transmitEffectChainSnapshot"))
        #expect(effectChainSource.contains("func receivePeerEffectChainSnapshot"))
        #expect(effectChainSource.contains("var receiveMasterEffectChainSnapshot"))
        #expect(effectChainSource.contains("effects: mixerBusSnapshot(id: \"tx-bus\")?.effectChain ?? []"))
        #expect(effectChainSource.contains("peakLimiterStageSnapshot") == false)
        #expect(callSessionAdapter.contains("case remotePeerMetadata(peerID: String, activeCodec: AudioCodecIdentifier?)"))
        #expect(callSessionAdapter.contains("case remoteRuntimeStatus(peerID: String, status: RTCRuntimeStatus)"))
        #expect(callSessionAdapter.contains("updateRuntimePackageReports"))
        #expect(callSessionAdapter.contains("setEnabledRoutes"))
        #expect(callSessionAdapter.contains("RTC.CallSessionFactory.makeSession"))
        #expect(callSessionAdapter.contains("Set(RTC.RouteKind.allCases)"))
        #expect(callSessionAdapter.contains("import RTCNativeWebRTC"))
        #expect(callSessionAdapter.contains("WebRTCNativeEngine"))
        #expect(callSessionAdapter.contains("selectionMode: .singleRoute") == false)
        #expect(callSessionAdapter.contains("makeRouteConfiguration"))
        #expect(callSessionAdapter.contains("RTCRuntimeStatusTransport.decode(message)"))
        #expect(callSessionAdapter.contains("PeerMetadataApplicationPayload(activeCodec: preferredAudioCodec)"))
        #expect(callSessionAdapter.contains("return .remotePeerMetadata(peerID: peerID, activeCodec: payload.activeCodec)"))
        #expect(diagnosticsSpec.contains("receive-master-effect-stage-peak-limiter"))
        #expect(audioSpec.contains("master effect chain の最後は PeakLimiter 固定"))
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
            vadGate: VADGate(configuration: VADGateConfiguration(
                attackDuration: 0.01,
                releaseDuration: 0.05,
                updateInterval: 0.02,
                speechThresholdOffsetDB: 6,
                silenceThresholdOffsetDB: 3,
                initialNoiseFloorDBFS: -60
            )),
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
        harness.inputBackend.emit(AudioStreamFrame(sequenceNumber: 3, format: .intercom, capturedAt: 102, samples: [0.4]))
        harness.inputBackend.emit(AudioStreamFrame(sequenceNumber: 4, format: .intercom, capturedAt: 103, samples: [0.4]))
        await Self.waitUntil { harness.callSession.sentAudioPackets.count >= 4 }

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

        #expect(harness.inputBackend.voiceProcessingConfigurations.last?.inputMuted == true)
        #expect(harness.inputBackend.voiceProcessingConfigurations.last?.soundIsolationEnabled == false)
        #expect(harness.callSession.localMuteValues.last == true)
        #expect(harness.callSession.sentControlMessages.contains(.peerMuteState(isMuted: true)))
        #expect(harness.callSession.sentControlMessages.contains(.keepalive))
    }

    @Test func viewModelAudioCheckRecordsAndSchedulesPlaybackThroughPackageOutput() async {
        let harness = Self.makeHarness(groups: [])

        harness.viewModel.startAudioCheck(recordDuration: .milliseconds(20), playbackDuration: .seconds(5))
        harness.inputBackend.emit(AudioStreamFrame(sequenceNumber: 1, format: .intercom, capturedAt: 100, samples: [0.5, -0.5]))
        await Self.waitUntil { harness.viewModel.audioCheckInputLevel > 0 }
        harness.viewModel.finishAudioCheckRecording(playbackDuration: .seconds(5))

        #expect(harness.viewModel.audioCheckPhase == .playing)
        #expect(harness.viewModel.audioCheckInputLevel > 0)
        #expect(harness.viewModel.audioCheckOutputLevel > 0)
        #expect(harness.outputBackend.scheduledFrames.count == 1)
        if let scheduledFrame = harness.outputBackend.scheduledFrames.first {
            #expect(scheduledFrame.samples == [0.5, -0.5])
        } else {
            Issue.record("Expected one audio check playback frame")
        }
    }

    @Test func viewModelResetAllSettingsKeepsGroupsAndRestoresAudioDefaults() {
        let harness = Self.makeHarness()

        harness.viewModel.setAudioSessionProfile(.voiceChat)
        harness.viewModel.setVADSensitivity(.noisy)
        harness.viewModel.setAACELDv2BitRate(128_000)
        harness.viewModel.setOpusBitRate(128_000)
        harness.viewModel.setMasterOutputVolume(2)
        harness.viewModel.setRemoteOutputVolume(peerID: "member-108", volume: 0.25)
        harness.viewModel.setRemoteSoundIsolationEnabled(peerID: "member-108", enabled: true)
        harness.viewModel.setReceiveMasterSoundIsolationEnabled(true)
        harness.viewModel.setDuckOthersEnabled(false)
        harness.viewModel.setRTCTransportRoute(.multipeer, enabled: false)
        harness.viewModel.setRTCTransportRoute(.webRTC, enabled: false)
        harness.viewModel.toggleOutputMute()
        harness.viewModel.resetAllSettings()

        #expect(harness.viewModel.audioSessionProfile == IntercomViewModel.defaultAudioSessionProfile)
        #expect(harness.viewModel.isDuckOthersEnabled == IntercomViewModel.defaultDuckOthersEnabled)
        #expect(harness.viewModel.vadSensitivity == IntercomViewModel.defaultVADSensitivity)
        #expect(harness.viewModel.preferredTransmitCodec == IntercomViewModel.defaultTransmitCodec)
        #expect(harness.viewModel.aacELDv2BitRate == IntercomViewModel.defaultAACELDv2BitRate)
        #expect(harness.viewModel.opusBitRate == IntercomViewModel.defaultOpusBitRate)
        #expect(harness.viewModel.masterOutputVolume == IntercomViewModel.defaultMasterOutputVolume)
        #expect(harness.viewModel.remoteOutputVolumes.isEmpty)
        #expect(harness.viewModel.remoteSoundIsolationEnabled.isEmpty)
        #expect(harness.viewModel.receiveMasterSoundIsolationEnabled == IntercomViewModel.defaultReceiveSoundIsolationEnabled)
        #expect(harness.viewModel.enabledRTCTransportRoutes == IntercomViewModel.defaultEnabledRTCTransportRoutes)
        #expect(!harness.viewModel.isOutputMuted)
        #expect(harness.viewModel.groups.count == IntercomSeedData.recentGroups.count)
        #expect(harness.callSession.remoteOutputVolumeValues.last?.peerID == "member-108")
        #expect(harness.callSession.remoteOutputVolumeValues.last?.volume == IntercomViewModel.defaultRemoteOutputVolume)
        #expect(harness.callSession.enabledRouteValues.last == IntercomViewModel.defaultEnabledRTCTransportRoutes)
        #expect(harness.callSession.outputMuteValues.last == false)
    }

    @Test func viewModelAppliesParticipantOutputVolumeToPlaybackAndRTC() {
        let harness = Self.makeHarness()
        let peerID = "member-108"

        harness.viewModel.setRemoteOutputVolume(peerID: peerID, volume: 0.25)
        harness.viewModel.scheduleOutputFrame(
            peerID: peerID,
            frame: RTC.AudioFrame(
                sequenceNumber: 1,
                format: RTC.AudioFormatDescriptor(sampleRate: 16_000, channelCount: 1),
                capturedAt: 100,
                samples: [0.5, -0.5]
            ),
            receivedAt: 100
        )

        #expect(harness.viewModel.remoteOutputVolume(for: peerID) == 0.25)
        #expect(harness.callSession.remoteOutputVolumeValues.last?.peerID == peerID)
        #expect(harness.callSession.remoteOutputVolumeValues.last?.volume == 0.25)
        #expect(harness.outputBackend.scheduledFrames.last?.samples == [0.125, -0.125])
    }

    @Test func viewModelAppliesReceiveMasterPeakLimiterAfterOutputGain() {
        let harness = Self.makeHarness()
        let peerID = "member-108"

        harness.viewModel.setMasterOutputVolume(2)
        harness.viewModel.scheduleOutputFrame(
            peerID: peerID,
            frame: RTC.AudioFrame(
                sequenceNumber: 1,
                format: RTC.AudioFormatDescriptor(sampleRate: 16_000, channelCount: 1),
                capturedAt: 100,
                samples: [0.75, -0.75, 0.25]
            ),
            receivedAt: 100
        )

        #expect(harness.outputBackend.scheduledFrames.last?.samples == [1, -1, 0.5])
        #expect(harness.viewModel.lastScheduledOutputRMS <= IntercomViewModel.receiveMasterPeakLimiterCeiling)
    }

    @Test func viewModelTracksReceiveVoiceIsolationControls() {
        let harness = Self.makeHarness()
        let peerID = "member-108"

        #expect(!harness.viewModel.isRemoteSoundIsolationEnabled(peerID: peerID))
        #expect(!harness.viewModel.receiveMasterSoundIsolationEnabled)
        #expect(harness.viewModel.receivePeerEffectChainSnapshot(peerID: peerID).stages.isEmpty)
        #expect(harness.viewModel.receiveMasterEffectChainSnapshot.stages.map(\.id) == ["sound-isolation", "peak-limiter"])
        #expect(harness.viewModel.receiveMasterEffectChainSnapshot.stages.last?.id == "peak-limiter")

        harness.viewModel.isAudioReady = true
        harness.viewModel.setRemoteSoundIsolationEnabled(peerID: peerID, enabled: true)
        harness.viewModel.setReceiveMasterSoundIsolationEnabled(true)

        #expect(harness.viewModel.isRemoteSoundIsolationEnabled(peerID: peerID))
        #expect(harness.viewModel.receiveMasterSoundIsolationEnabled)
        if harness.viewModel.supportsSoundIsolation {
            #expect(harness.viewModel.receivePeerEffectChainSnapshot(peerID: peerID).stages.first?.state == .active)
            #expect(harness.viewModel.receiveMasterEffectChainSnapshot.stages.first?.state == .active)
        } else {
            #expect(harness.viewModel.receivePeerEffectChainSnapshot(peerID: peerID).stages.first?.state == .unavailable)
            #expect(harness.viewModel.receiveMasterEffectChainSnapshot.stages.first?.state == .unavailable)
        }
        #expect(harness.viewModel.remoteOutputVolume(for: peerID) == IntercomViewModel.defaultRemoteOutputVolume)
        #expect(harness.viewModel.masterOutputVolume == IntercomViewModel.defaultMasterOutputVolume)
    }

    @Test func viewModelTracksRemoteCodecMetadataPerPeer() throws {
        let harness = Self.makeHarness()
        let peerID = "member-108"

        harness.viewModel.selectGroup(IntercomSeedData.recentGroups[0])
        harness.viewModel.handleTransportEvent(.connected(peerIDs: [peerID]))
        harness.viewModel.handleTransportEvent(.authenticated(peerIDs: [peerID]))
        harness.viewModel.handleTransportEvent(.remotePeerMetadata(peerID: peerID, activeCodec: .opus))

        let remoteMember = try #require(harness.viewModel.selectedGroup?.members.first { $0.id == peerID })
        #expect(remoteMember.connectionState == .connected)
        #expect(remoteMember.authenticationState == .authenticated)
        #expect(remoteMember.activeCodec == .opus)
    }

    @Test func viewModelExposesTransmitEffectChainFromRuntimeSettings() {
        let harness = Self.makeHarness()

        #expect(harness.viewModel.transmitEffectChainSnapshot.stages.map(\.id) == [
            "sound-isolation",
            "vad-gate",
            "dynamics-processor",
            "peak-limiter"
        ])

        harness.viewModel.isAudioReady = true
        harness.viewModel.setSoundIsolationEnabled(false)

        #expect(harness.viewModel.transmitEffectChainSnapshot.stages.first?.state == .bypassed)
        #expect(harness.viewModel.transmitEffectChainSnapshot.stages.last?.id == "peak-limiter")
        #expect(harness.viewModel.transmitEffectChainSnapshot.stages.last?.state == .active)
    }

    @Test func viewModelPublishesPackageRuntimeReportsForDiagnosticsAndRTC() throws {
        let harness = Self.makeHarness()
        let peerID = "member-108"

        harness.viewModel.selectGroup(IntercomSeedData.recentGroups[0])
        harness.viewModel.setRemoteSoundIsolationEnabled(peerID: peerID, enabled: true)
        harness.viewModel.publishRuntimePackageReports(force: true, now: 100)

        let reports = try #require(harness.callSession.runtimePackageReports.last)
        #expect(reports.map(\.package).contains("AudioMixer"))
        #expect(reports.map(\.package).contains("Codec"))
        #expect(reports.map(\.package).contains("VADGate"))
        #expect(reports.map(\.package).contains("SessionManager"))

        let mixerReport = try #require(reports.first { $0.package == "AudioMixer" && $0.kind == "snapshot" })
        let mixerSnapshot = try mixerReport.decodeJSON(AudioMixerSnapshot.self)
        #expect(mixerSnapshot.buses.first { $0.id == "tx-bus" }?.effectChain.map(\.id) == [
            "sound-isolation",
            "vad-gate",
            "dynamics-processor",
            "peak-limiter"
        ])
        #expect(mixerSnapshot.buses.first { $0.id == "rx-master" }?.effectChain.map(\.id) == [
            "sound-isolation",
            "peak-limiter"
        ])
        #expect(mixerSnapshot.routes.contains {
            $0.sourceBusID == "rx-peer-\(peerID)" && $0.destinationBusID == "rx-master"
        })
        #expect(mixerSnapshot.graph.edges.contains {
            $0.kind == .busSignal && $0.sourceBusID == "tx-bus" && $0.destinationBusID == "tx-bus"
        })

        let codecReport = try #require(reports.first { $0.package == "Codec" && $0.kind == "runtimeReport" })
        let codecRuntime = try codecReport.decodeJSON(CodecRuntimeReport.self)
        #expect(codecRuntime.requestedConfiguration.codec.rawValue == harness.viewModel.preferredTransmitCodec.rawValue)

        let vadReport = try #require(reports.first { $0.package == "VADGate" && $0.kind == "runtimeSnapshot" })
        let vadRuntime = try vadReport.decodeJSON(VADGateRuntimeSnapshot.self)
        #expect(vadRuntime.configuration == harness.viewModel.vadSensitivity.configuration)
    }

    @Test func effectChainDisplayPreservesRuntimeRegisteredOrder() {
        func effect(
            id: String,
            typeName: String,
            index: Int,
            state: MixerEffectState,
            shortLabel: String,
            detail: String
        ) -> MixerEffectSnapshot {
            MixerEffectSnapshot(
                id: id,
                typeName: typeName,
                index: index,
                state: state,
                parameters: [
                    MixerEffectParameterSnapshot(id: "package", value: typeName),
                    MixerEffectParameterSnapshot(id: "name", value: shortLabel),
                    MixerEffectParameterSnapshot(id: "shortLabel", value: shortLabel),
                    MixerEffectParameterSnapshot(id: "detail", value: detail),
                    MixerEffectParameterSnapshot(id: "runtimeState", value: state.rawValue)
                ]
            )
        }
        let runtimeChain = AudioEffectChainSnapshot(
            id: "custom",
            effects: [
                effect(
                    id: "noise-reducer",
                    typeName: "NoiseReducer",
                    index: 0,
                    state: .active,
                    shortLabel: "NR",
                    detail: "Ready"
                ),
                effect(
                    id: "sound-isolation",
                    typeName: "SoundIsolation",
                    index: 1,
                    state: .active,
                    shortLabel: "SI",
                    detail: "Enabled"
                ),
                effect(
                    id: "custom-tail",
                    typeName: "CustomEffect",
                    index: 2,
                    state: .bypassed,
                    shortLabel: "Tail",
                    detail: "Bypassed"
                )
            ]
        )

        let displayStages = runtimeChain.stages.map(EffectChainStage.init(snapshot:))

        #expect(displayStages.map(\.id) == ["noise-reducer", "sound-isolation", "custom-tail"])
        #expect(runtimeChain.compactSummary == "NR, SI, Tail")
        #expect(displayStages.map(\.state) == [.passing, .passing, .idle])
    }

    @Test func viewModelKeepsCodecUISettingsAsRequestedValues() {
        let harness = Self.makeHarness()

        #expect(harness.viewModel.preferredTransmitCodec == .mpeg4AACELDv2)
        #expect(harness.viewModel.aacELDv2BitRate == 32_000)
        #expect(harness.viewModel.opusBitRate == 32_000)
        #expect(harness.callSession.preferredCodecs.last == .mpeg4AACELDv2)
        #expect(harness.callSession.codecOptions.last?.aacELDv2BitRate == 32_000)
        #expect(harness.callSession.codecOptions.last?.opusBitRate == 32_000)

        harness.viewModel.setPreferredTransmitCodec(.mpeg4AACELDv2)
        harness.viewModel.setAACELDv2BitRate(11_000)
        harness.viewModel.setOpusBitRate(129_000)

        #expect(harness.viewModel.preferredTransmitCodec == .mpeg4AACELDv2)
        #expect(harness.viewModel.aacELDv2BitRate == 12_000)
        #expect(harness.viewModel.opusBitRate == 128_000)
        #expect(harness.callSession.preferredCodecs.last == .mpeg4AACELDv2)
        #expect(harness.callSession.codecOptions.last?.aacELDv2BitRate == 12_000)
        #expect(harness.callSession.codecOptions.last?.opusBitRate == 128_000)
    }

    @Test func viewModelAppliesAudioSessionMatrixProfilesThroughSessionManager() {
        let harness = Self.makeHarness()

        #expect(harness.viewModel.audioSessionProfile == .echoCancelledInput)
        #expect(harness.viewModel.isSessionEchoCancellationEnabled)
        #expect(harness.viewModel.isDuckOthersEnabled)

        harness.viewModel.setSessionEchoCancellationEnabled(true)
        var applied = harness.audioSessionBackend.appliedConfigurations.last
        #expect(applied?.mode == .default)
        #expect(applied?.prefersEchoCancelledInput == true)
        #expect(applied?.options.contains(.defaultToSpeaker) == false)

        harness.viewModel.setSessionEchoCancellationEnabled(false)
        applied = harness.audioSessionBackend.appliedConfigurations.last
        #expect(applied?.mode == .default)
        #expect(applied?.prefersEchoCancelledInput == false)
        #expect(harness.viewModel.audioSessionProfile == .standard)

        harness.viewModel.setSpeakerOutputEnabled(true)
        applied = harness.audioSessionBackend.appliedConfigurations.last
        #expect(applied?.mode == .default)
        #expect(applied?.prefersEchoCancelledInput == true)
        #expect(applied?.options.contains(.defaultToSpeaker) == true)
        #expect(harness.viewModel.audioSessionProfile == .standard)

        harness.viewModel.setAudioSessionModeProfile(.voiceChat)
        harness.viewModel.setSpeakerOutputEnabled(true)
        applied = harness.audioSessionBackend.appliedConfigurations.last
        #expect(applied?.mode == .voiceChat)
        #expect(applied?.prefersEchoCancelledInput == nil)
        #expect(applied?.options.contains(.defaultToSpeaker) == true)
    }

    @Test func viewModelLoadsAndPersistsAppAudioSettings() {
        let settingsStore = InMemoryAppSettingsStore(settings: AppSettings(
            audioSessionProfile: .voiceChat,
            vadSensitivity: .noisy,
            preferredTransmitCodec: .opus,
            aacELDv2BitRate: 11_000,
            opusBitRate: 129_000
        ))
        let harness = Self.makeHarness(appSettingsStore: settingsStore)

        #expect(harness.viewModel.audioSessionProfile == .voiceChat)
        #expect(harness.viewModel.vadSensitivity == .noisy)
        #expect(harness.viewModel.preferredTransmitCodec == .opus)
        #expect(harness.viewModel.aacELDv2BitRate == 12_000)
        #expect(harness.viewModel.opusBitRate == 128_000)
        #expect(harness.callSession.preferredCodecs.last == .opus)
        #expect(harness.callSession.codecOptions.last?.aacELDv2BitRate == 12_000)
        #expect(harness.callSession.codecOptions.last?.opusBitRate == 128_000)

        harness.viewModel.setAudioSessionProfile(.echoCancelledInput)
        harness.viewModel.setVADSensitivity(.lowNoise)
        harness.viewModel.setPreferredTransmitCodec(.mpeg4AACELDv2)
        harness.viewModel.setAACELDv2BitRate(40_000)

        let saved = settingsStore.load()
        #expect(saved.audioSessionProfile == .echoCancelledInput)
        #expect(saved.vadSensitivity == .lowNoise)
        #expect(saved.preferredTransmitCodec == .mpeg4AACELDv2)
        #expect(saved.aacELDv2BitRate == 40_000)
        #expect(saved.opusBitRate == 128_000)
    }

    @Test func viewModelLoadsPersistsAndAppliesRTCTransportRouteOptOut() {
        let defaultHarness = Self.makeHarness()
        #expect(defaultHarness.viewModel.enabledRTCTransportRoutes == Set(RTC.RouteKind.allCases))
        #expect(defaultHarness.callSession.enabledRouteValues.last == Set(RTC.RouteKind.allCases))

        let settingsStore = InMemoryAppSettingsStore(settings: AppSettings(
            enabledRTCTransportRoutes: []
        ))
        let harness = Self.makeHarness(appSettingsStore: settingsStore)

        #expect(harness.viewModel.enabledRTCTransportRoutes.isEmpty)
        #expect(harness.callSession.enabledRouteValues.last?.isEmpty == true)
        #expect(!harness.viewModel.isRTCTransportRouteEnabled(.multipeer))
        #expect(harness.viewModel.canToggleRTCTransportRoute(.multipeer))
        #expect(harness.viewModel.canToggleRTCTransportRoute(.webRTC))

        harness.viewModel.setRTCTransportRoute(.webRTC, enabled: true)

        #expect(harness.viewModel.enabledRTCTransportRoutes == [.webRTC])
        #expect(settingsStore.load().enabledRTCTransportRoutes == [.webRTC])
        #expect(harness.callSession.enabledRouteValues.last == [.webRTC])

        harness.viewModel.setRTCTransportRoute(.multipeer, enabled: true)

        #expect(harness.viewModel.enabledRTCTransportRoutes == Set(RTC.RouteKind.allCases))
        #expect(settingsStore.load().enabledRTCTransportRoutes == Set(RTC.RouteKind.allCases))
        #expect(harness.callSession.enabledRouteValues.last == Set(RTC.RouteKind.allCases))

        harness.viewModel.setRTCTransportRoute(.webRTC, enabled: false)

        #expect(harness.viewModel.enabledRTCTransportRoutes == [.multipeer])
        #expect(settingsStore.load().enabledRTCTransportRoutes == [.multipeer])
        #expect(harness.callSession.enabledRouteValues.last == [.multipeer])

        harness.viewModel.setRTCTransportRoute(.multipeer, enabled: false)

        #expect(harness.viewModel.enabledRTCTransportRoutes.isEmpty)
        #expect(settingsStore.load().enabledRTCTransportRoutes.isEmpty)
        #expect(harness.callSession.enabledRouteValues.last?.isEmpty == true)
    }

    @Test func changingRTCTransportRoutesStopsActiveConnectionBeforeApplyingPolicy() {
        let harness = Self.makeHarness()

        harness.viewModel.selectGroup(IntercomSeedData.recentGroups[0])
        harness.viewModel.setRTCTransportRoute(.webRTC, enabled: false)

        #expect(harness.callSession.disconnectCallCount == 1)
        #expect(harness.viewModel.connectionState == .idle)
        #expect(harness.callSession.connectedGroup == nil)
        #expect(harness.callSession.enabledRouteValues.last == [.multipeer])
    }

    @Test func diagnosticsSnapshotSummarizesCurrentAppState() {
        let harness = Self.makeHarness()
        let snapshot = harness.viewModel.diagnosticsSnapshot

        #expect(snapshot.transportSummary == "TRANSPORT RecordingCallSession")
        #expect(snapshot.audio.summary.contains("TX 0"))
        #expect(snapshot.connectionSummary == "PEERS 0")

        let overviewRows = harness.viewModel.diagnosticsOverviewRows
        #expect(overviewRows.map(\.id) == ["call", "network", "invite"])
        #expect(overviewRows.map(\.title) == ["Call", "Network Quality", "Invite"])
        #expect(overviewRows.contains { $0.accessibilityIdentifier == "audioSessionSummaryLabel" } == false)
        #expect(overviewRows.contains { $0.accessibilityIdentifier == "audioInputProcessingSummaryLabel" } == false)
        #expect(overviewRows.contains { $0.accessibilityIdentifier == "playbackDebugSummaryLabel" } == false)
        #expect(overviewRows.contains { $0.accessibilityIdentifier == "codecDebugSummaryLabel" } == false)
        #expect(overviewRows.contains { $0.accessibilityIdentifier == "audioDebugSummaryLabel" } == false)
        #expect(overviewRows.contains { $0.accessibilityIdentifier == "authenticationDebugSummaryLabel" } == false)
    }

    private struct Harness {
        let viewModel: IntercomViewModel
        let callSession: RecordingCallSession
        let groupStore: InMemoryGroupStore
        let audioSessionBackend: FakeAudioSessionBackend
        let inputBackend: FakeInputStreamBackend
        let outputBackend: FakeOutputStreamBackend
    }

    private static func makeHarness(
        groups: [IntercomGroup]? = nil,
        credentialStore: GroupCredentialStoring? = nil,
        appSettingsStore: AppSettingsStoring? = nil
    ) -> Harness {
        let groups = groups ?? IntercomSeedData.recentGroups
        let credentialStore = credentialStore ?? InMemoryGroupCredentialStore()
        let callSession = RecordingCallSession()
        let groupStore = InMemoryGroupStore(groups: groups)
        let audioSessionBackend = FakeAudioSessionBackend()
        let inputBackend = FakeInputStreamBackend()
        let outputBackend = FakeOutputStreamBackend()
        let identityStore = InMemoryLocalMemberIdentityStore(
            identity: LocalMemberIdentity(memberID: groups.first?.members.first?.id ?? "member-local", displayName: "You")
        )
        let viewModel = IntercomViewModel(
            groups: groups,
            callSession: callSession,
            credentialStore: credentialStore,
            groupStore: groupStore,
            appSettingsStore: appSettingsStore,
            localMemberIdentityStore: identityStore,
            audioSessionManager: AudioSessionManager(backend: audioSessionBackend),
            audioInputCapture: AudioInputStreamCapture(
                configuration: .intercom(voiceProcessing: IntercomViewModel.defaultVoiceProcessingConfiguration()),
                backend: inputBackend
            ),
            audioOutputRenderer: AudioOutputStreamRenderer(configuration: .intercom, backend: outputBackend),
            callTicker: NoOpCallTicker()
        )
        return Harness(
            viewModel: viewModel,
            callSession: callSession,
            groupStore: groupStore,
            audioSessionBackend: audioSessionBackend,
            inputBackend: inputBackend,
            outputBackend: outputBackend
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
    private(set) var codecOptions: [(aacELDv2BitRate: Int, opusBitRate: Int)] = []
    private(set) var localMuteValues: [Bool] = []
    private(set) var outputMuteValues: [Bool] = []
    private(set) var remoteOutputVolumeValues: [(peerID: String, volume: Float)] = []
    private(set) var enabledRouteValues: [Set<RTC.RouteKind>] = []
    private(set) var runtimePackageReports: [[RTCRuntimePackageReport]] = []
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

    func setAudioCodecOptions(aacELDv2BitRate: Int, opusBitRate: Int) {
        codecOptions.append((aacELDv2BitRate, opusBitRate))
    }

    func setLocalMute(_ muted: Bool) {
        localMuteValues.append(muted)
    }

    func setOutputMute(_ muted: Bool) {
        outputMuteValues.append(muted)
    }

    func setRemoteOutputVolume(peerID: String, volume: Float) {
        remoteOutputVolumeValues.append((peerID, volume))
    }

    func setEnabledRoutes(_ routes: Set<RTC.RouteKind>) {
        enabledRouteValues.append(routes)
    }

    func updateRuntimePackageReports(_ reports: [RTCRuntimePackageReport]) {
        runtimePackageReports.append(reports)
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
    private(set) var voiceProcessingConfigurations: [SessionManager.AudioInputVoiceProcessingConfiguration] = []
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

    func updateVoiceProcessing(_ configuration: SessionManager.AudioInputVoiceProcessingConfiguration) throws {
        voiceProcessingConfigurations.append(configuration)
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
