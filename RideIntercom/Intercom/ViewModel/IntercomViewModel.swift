import CryptoKit
import AVFoundation
import AVFAudio
import Codec
import Foundation
import Observation
import OSLog
import RTC
import SessionManager
import VADGate

@MainActor
@Observable
final class IntercomViewModel {
    static let pendingMemberPrefix = "pending-"
    static let pendingInviteMemberPrefix = "invite-pending-"
    nonisolated static let defaultSoundIsolationEnabled = true
    nonisolated static let defaultTransmitCodec: AudioCodecIdentifier = .pcm16
    nonisolated static let otherAudioDuckingHoldDuration: TimeInterval = 1.0

    var groups: [IntercomGroup]
    var selectedGroup: IntercomGroup?
    var activeGroupID: UUID?
    var connectionState: CallConnectionState = .idle
    var isMuted = false
    var isVoiceActive = false
    var isAudioReady = false
    var audioErrorMessage: String?
    var selectedInputPort: AudioPortInfo = .systemDefault
    var selectedOutputPort: AudioPortInfo = .systemDefault
    var isDuckOthersEnabled = false
    var voiceActivityDetectionThreshold: Float = AudioTransmissionController.defaultVoiceActivityThreshold
    var isSoundIsolationEnabled = IntercomViewModel.defaultSoundIsolationEnabled
    var preferredTransmitCodec: AudioCodecIdentifier = IntercomViewModel.defaultTransmitCodec
    var isOutputMuted = false
    var isMicrophoneCaptureRunning: Bool {
        isAudioReady
    }

    var availableInputPorts: [AudioPortInfo] {
        deduplicatedPorts(audioSessionSnapshot.availableInputs.map(AudioPortInfo.init(device:)))
    }
    var availableOutputPorts: [AudioPortInfo] {
        deduplicatedPorts(audioSessionSnapshot.availableOutputs.map(AudioPortInfo.init(device:)))
    }
    var isAudioDeviceSelectionLive: Bool { isAudioReady || audioSessionSnapshot.isActive }
    var supportsAdvancedMixingOptions: Bool { true }
    var isOtherAudioDuckingActive: Bool { isOtherAudioDuckingActiveInternal }
    var diagnosticsInputLevel: Float {
        if audioCheckPhase == .recording {
            return audioCheckInputLevel
        }
        guard let localMember = selectedGroup?.members.first, !isMuted else { return 0 }
        return localMember.voiceLevel
    }
    var diagnosticsInputPeakLevel: Float {
        if audioCheckPhase == .recording {
            return audioCheckInputPeakLevel
        }
        guard let localMember = selectedGroup?.members.first, !isMuted else { return 0 }
        return localMember.voicePeakLevel
    }
    var diagnosticsOutputLevel: Float {
        if audioCheckPhase == .playing {
            return audioCheckOutputLevel
        }
        return lastScheduledOutputRMS
    }
    var diagnosticsOutputPeakLevel: Float {
        if audioCheckPhase == .playing {
            return audioCheckOutputPeakLevel
        }
        return lastScheduledOutputPeakRMS
    }
    var audioCheckPhase: AudioCheckPhase = .idle
    var audioCheckInputLevel: Float = 0
    var audioCheckInputPeakLevel: Float = 0
    var audioCheckOutputLevel: Float = 0
    var audioCheckOutputPeakLevel: Float = 0
    var audioCheckStatusMessage = "Audio check idle"
    var sentVoicePacketCount = 0
    var receivedVoicePacketCount = 0
    var playedAudioFrameCount = 0
    var lastScheduledOutputRMS: Float = 0
    var lastScheduledOutputPeakRMS: Float = 0
    var scheduledOutputBatchCount = 0
    var scheduledOutputFrameCount = 0
    var connectedPeerIDs: [String] = []
    var authenticatedPeerIDs: [String] = []
    var localNetworkStatus: LocalNetworkStatus = .idle
    var lastLocalNetworkPeerID: String?
    var lastLocalNetworkEventAt: TimeInterval?
    var lastReceivedAudioAt: TimeInterval?
    var lastAudibleReceivedAudioAt: TimeInterval?
    var droppedAudioPacketCount = 0
    var jitterQueuedFrameCount = 0
    var inviteStatusMessage: String?
    var uiEventRevision = 0
    let callSession: CallSession
    let audioSessionManager: SessionManager.AudioSessionManager
    let audioInputCapture: SessionManager.AudioInputStreamCapture
    let audioOutputRenderer: SessionManager.AudioOutputStreamRenderer
    let audioInputVoiceProcessingManager: SessionManager.AudioInputVoiceProcessingManager?
    let callTicker: CallTicking
    let credentialStore: GroupCredentialStoring
    let credentialProvider: any GroupCredentialProviding
    let groupStore: GroupStoring
    let localMemberIdentity: LocalMemberIdentity
    let remoteTalkerTimeout: TimeInterval
    var audioTransmissionController: AudioTransmissionController
    var audioSessionSnapshot: SessionManager.AudioSessionSnapshot
    var remoteVoiceReceivedAt: [String: TimeInterval] = [:]
    var localVoicePeakWindow = VoicePeakWindow()
    var remoteVoicePeakWindows: [String: VoicePeakWindow] = [:]
    var playbackOutputPeakWindow = VoicePeakWindow()
    var audioCheckInputPeakWindow = VoicePeakWindow()
    var audioCheckOutputPeakWindow = VoicePeakWindow()
    var audioCheckRecordedSamples: [Float] = []
    var audioCheckTask: Task<Void, Never>?
    var audioCheckOwnsAudioPipeline = false
    var isLocalStandbyOnly = false
    var nextAudioFrameID = 1
    var isOtherAudioDuckingActiveInternal = false

    init(
        groups: [IntercomGroup]? = nil,
        callSession: CallSession? = nil,
        credentialStore: GroupCredentialStoring? = nil,
        groupStore: GroupStoring? = nil,
        localMemberIdentityStore: LocalMemberIdentityStoring? = nil,
        audioSessionManager: SessionManager.AudioSessionManager? = nil,
        audioInputCapture: SessionManager.AudioInputStreamCapture? = nil,
        audioOutputRenderer: SessionManager.AudioOutputStreamRenderer? = nil,
        audioInputVoiceProcessingManager: SessionManager.AudioInputVoiceProcessingManager? = nil,
        audioTransmissionController: AudioTransmissionController? = nil,
        callTicker: CallTicking? = nil,
        remoteTalkerTimeout: TimeInterval = 0.6
    ) {
        let localMemberIdentityStore = localMemberIdentityStore ?? InMemoryLocalMemberIdentityStore()
        let localMemberIdentity = localMemberIdentityStore.loadOrCreate()
        let groupStore = groupStore ?? InMemoryGroupStore()
        let storedGroups = groupStore.loadGroups()
        self.groups = groups ?? storedGroups
        self.callSession = callSession ?? RideIntercomCallSessionAdapter(memberID: localMemberIdentity.memberID)
        let sessionManager = audioSessionManager ?? SessionManager.AudioSessionManager()
        self.audioSessionManager = sessionManager
        let audioInputPipeline = audioInputCapture.map {
            AudioInputPipeline(capture: $0, voiceProcessingManager: audioInputVoiceProcessingManager)
        } ?? Self.makeDefaultAudioInputPipeline()
        self.audioInputCapture = audioInputPipeline.capture
        self.audioInputVoiceProcessingManager = audioInputVoiceProcessingManager ?? audioInputPipeline.voiceProcessingManager
        self.audioOutputRenderer = audioOutputRenderer ?? Self.makeDefaultAudioOutputRenderer()
        let initialVoiceActivityDetectionThreshold = AudioTransmissionController.defaultVoiceActivityThreshold
        self.voiceActivityDetectionThreshold = initialVoiceActivityDetectionThreshold
        self.audioTransmissionController = audioTransmissionController ?? AudioTransmissionController()
        self.callTicker = callTicker ?? RepeatingCallTicker()
        self.credentialStore = credentialStore ?? InMemoryGroupCredentialStore()
        self.credentialProvider = DefaultGroupCredentialProvider()
        self.groupStore = groupStore
        self.localMemberIdentity = localMemberIdentity
        self.audioSessionSnapshot = (try? sessionManager.snapshot()) ?? Self.defaultAudioSessionSnapshot()
        self.remoteTalkerTimeout = remoteTalkerTimeout
        self.audioTransmissionController.setVoiceActivityThreshold(initialVoiceActivityDetectionThreshold)
        self.selectedInputPort = AudioPortInfo(device: audioSessionSnapshot.currentInput)
        self.selectedOutputPort = AudioPortInfo(device: audioSessionSnapshot.currentOutput)

        self.callSession.onEvent = { [weak self] event in
            DispatchQueue.main.async { self?.handleTransportEvent(event) }
        }
        self.audioSessionManager.setRuntimeEventHandler { [weak self] event in
            DispatchQueue.main.async { self?.handleAudioSessionRuntimeEvent(event) }
        }
        self.audioInputCapture.setRuntimeEventHandler { [weak self] event in
            DispatchQueue.main.async { self?.handleAudioStreamRuntimeEvent(event) }
        }
        self.callTicker.onTick = { [weak self] now in
            self?.handleCallTick(now: now)
        }
    }
}
