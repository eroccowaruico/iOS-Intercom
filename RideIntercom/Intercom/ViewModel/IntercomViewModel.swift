import CryptoKit
import AVFoundation
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
    nonisolated static let normalMasterOutputVolume: Float = 1
    nonisolated static let maximumMasterOutputVolume: Float = 2
    nonisolated static let defaultSoundIsolationEnabled = true
    nonisolated static let defaultTransmitCodec: AudioCodecIdentifier = .pcm16
    nonisolated static let defaultHEAACv2Quality: HEAACv2Quality = .medium
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
    var heAACv2Quality: HEAACv2Quality = IntercomViewModel.defaultHEAACv2Quality
    var masterOutputVolume: Float = IntercomViewModel.normalMasterOutputVolume
    var isOutputMuted = false
    var remoteOutputVolumes: [String: Float] = [:]
    var isMicrophoneCaptureRunning: Bool {
        isAudioReady && !isMuted
    }

    var availableInputPorts: [AudioPortInfo] { audioSessionManager.availableInputPorts }
    var availableOutputPorts: [AudioPortInfo] { audioSessionManager.availableOutputPorts }
    var isAudioDeviceSelectionLive: Bool { audioSessionManager.isConfigured }
    var supportsAdvancedMixingOptions: Bool { audioSessionManager.supportsAdvancedMixingOptions }
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
    var transmitFallbackCount = 0
    var lastTransmitFallbackSummary: String?
    var uiEventRevision = 0
    let callSession: CallSession
    let audioSessionManager: AudioSessionManager
    let audioInputMonitor: AudioInputMonitoring
    let callTicker: CallTicking
    let audioFramePlayer: AudioFramePlaying
    let credentialStore: GroupCredentialStoring
    let credentialProvider: any GroupCredentialProviding
    let groupStore: GroupStoring
    let localMemberIdentity: LocalMemberIdentity
    let remoteTalkerTimeout: TimeInterval
    var audioTransmissionController: AudioTransmissionController
    var jitterBuffer: JitterBuffer
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
    let diagnosticsLogger = Logger(subsystem: "com.yowamushi-inc.RideIntercom", category: "codec-diagnostics")

    init(
        groups: [IntercomGroup]? = nil,
        callSession: CallSession? = nil,
        credentialStore: GroupCredentialStoring? = nil,
        groupStore: GroupStoring? = nil,
        localMemberIdentityStore: LocalMemberIdentityStoring? = nil,
        audioSessionManager: AudioSessionManager? = nil,
        audioInputMonitor: AudioInputMonitoring? = nil,
        audioTransmissionController: AudioTransmissionController? = nil,
        callTicker: CallTicking? = nil,
        audioFramePlayer: AudioFramePlaying? = nil,
        jitterBuffer: JitterBuffer? = nil,
        remoteTalkerTimeout: TimeInterval = 0.6
    ) {
        let localMemberIdentityStore = localMemberIdentityStore ?? InMemoryLocalMemberIdentityStore()
        let localMemberIdentity = localMemberIdentityStore.loadOrCreate()
        let groupStore = groupStore ?? InMemoryGroupStore()
        let storedGroups = groupStore.loadGroups()
        self.groups = groups ?? storedGroups
        self.callSession = callSession ?? RideIntercomCallSessionAdapter(memberID: localMemberIdentity.memberID)
        self.audioSessionManager = audioSessionManager ?? AudioSessionManager()
        self.audioInputMonitor = audioInputMonitor ?? SystemAudioInputMonitor()
        let initialVoiceActivityDetectionThreshold = AudioTransmissionController.defaultVoiceActivityThreshold
        self.voiceActivityDetectionThreshold = initialVoiceActivityDetectionThreshold
        self.audioTransmissionController = audioTransmissionController ?? AudioTransmissionController()
        self.callTicker = callTicker ?? RepeatingCallTicker()
        self.audioFramePlayer = audioFramePlayer ?? Self.makeDefaultAudioFramePlayer()
        self.credentialStore = credentialStore ?? InMemoryGroupCredentialStore()
        self.credentialProvider = DefaultGroupCredentialProvider()
        self.groupStore = groupStore
        self.localMemberIdentity = localMemberIdentity
        self.jitterBuffer = jitterBuffer ?? JitterBuffer()
        self.remoteTalkerTimeout = remoteTalkerTimeout
        self.audioTransmissionController.setVoiceActivityThreshold(initialVoiceActivityDetectionThreshold)
        self.selectedInputPort = self.audioSessionManager.selectedInputPort
        self.selectedOutputPort = self.audioSessionManager.selectedOutputPort
        self.isDuckOthersEnabled = self.audioSessionManager.isDuckOthersEnabled
        self.audioInputMonitor.setOtherAudioDuckingEnabled(false)

        self.callSession.onEvent = { [weak self] event in
            DispatchQueue.main.async { self?.handleTransportEvent(event) }
        }
        self.audioSessionManager.onAvailablePortsChanged = { [weak self] in
            self?.handleAvailableAudioPortsChanged()
        }
        self.audioInputMonitor.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.handleMicrophoneLevel(level) }
        }
        self.audioInputMonitor.onSamples = { [weak self] samples in
            DispatchQueue.main.async { self?.handleMicrophoneSamples(samples) }
        }
        self.callTicker.onTick = { [weak self] now in
            self?.handleCallTick(now: now)
        }
        self.isSoundIsolationEnabled = self.audioInputMonitor.isSoundIsolationEnabled
    }
}
