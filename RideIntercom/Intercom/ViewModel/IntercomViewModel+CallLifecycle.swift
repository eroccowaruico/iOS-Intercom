import AVFoundation
import Codec
import CryptoKit
import Foundation
import OSLog
import RTC
import SessionManager
import VADGate

extension IntercomViewModel {
    func connectLocal() {
        guard let selectedGroup else { return }

        if let activeGroupID,
           activeGroupID != selectedGroup.id,
           hasAnyActiveGroupConnection {
            disconnect()
        }

        if activeGroupID != selectedGroup.id {
            activeGroupID = selectedGroup.id
            resetConnectionRuntimeState()
        }

        isLocalStandbyOnly = false
        connectionState = connectedPeerIDs.isEmpty ? .localConnecting : .localConnected
        markMembers(connectionState == .localConnected ? .connected : .connecting)
        let shouldStartOrPromoteLocalConnection =
            authenticatedPeerIDs.isEmpty &&
            connectedPeerIDs.isEmpty &&
            localNetworkStatus != .connected

        if shouldStartOrPromoteLocalConnection {
            var group = selectedGroup
            if let credential = credentialStore.credential(for: selectedGroup.id) {
                group.accessSecret = credential.secret
            }
            callSession.setPreferredAudioCodec(preferredTransmitCodec)
            callSession.connect(group: group)
        }
        if !authenticatedPeerIDs.isEmpty {
            startActiveCallAfterAuthenticatedPeer()
        }
    }

    func startActiveCallAfterAuthenticatedPeer() {
        guard !isLocalStandbyOnly,
              !authenticatedPeerIDs.isEmpty,
              startAudioPipelineIfNeeded() else { return }

        connectionState = .localConnected
        markConnectedMembers(peerIDs: connectedPeerIDs)
    }

    func startAudioPipelineIfNeeded() -> Bool {
        if isAudioReady {
            return true
        }

        do {
            callSession.startMedia()
            try audioSessionManager.configureForIntercom()
            refreshOtherAudioDuckingState()
            try audioInputMonitor.start()
            audioInputMonitor.setInputMuted(isMuted)
            try audioFramePlayer.start()
            callTicker.start()
            isAudioReady = true
            refreshOtherAudioDuckingState()
            audioErrorMessage = nil
            return true
        } catch {
            callSession.stopMedia()
            isAudioReady = false
            audioErrorMessage = audioSetupMessage(for: error)
            return false
        }
    }

    func stopAudioPipeline(deactivateSession: Bool = false) {
        setOtherAudioDuckingActive(false)
        callSession.stopMedia()
        audioInputMonitor.stop()
        audioFramePlayer.stop()
        callTicker.stop()
        if deactivateSession {
            try? audioSessionManager.deactivate()
        }
        isAudioReady = false
    }

    func startLocalStandby() {
        guard let selectedGroup,
              !isAudioReady,
              localNetworkStatus == .idle,
              selectedGroup.id == activeGroupID else { return }

        isLocalStandbyOnly = true
        var group = selectedGroup
        if let credential = credentialStore.credential(for: selectedGroup.id) {
            group.accessSecret = credential.secret
        }
        callSession.setPreferredAudioCodec(preferredTransmitCodec)
        callSession.startStandby(group: group)
    }

    func audioSetupMessage(for error: Error) -> String {
        guard let audioInputError = error as? AudioInputMonitorError else {
            return "Audio setup failed"
        }

        switch audioInputError {
        case .microphonePermissionRequestPending:
            return "Microphone permission requested. Allow access, then connect again."
        case .microphonePermissionDenied:
            return "Microphone access is off. Enable it in Privacy & Security, then connect again."
        }
    }

    func disconnect() {
        let disconnectingGroupID = activeGroupID
        audioCheckTask?.cancel()
        stopAudioPipeline()
        callSession.disconnect()
        connectionState = .idle
        isVoiceActive = false
        remoteVoiceReceivedAt.removeAll()
        resetVoiceLevelWindows()
        connectedPeerIDs = []
        authenticatedPeerIDs = []
        isLocalStandbyOnly = false
        localNetworkStatus = .idle
        lastLocalNetworkPeerID = nil
        lastLocalNetworkEventAt = nil
        lastReceivedAudioAt = nil
        droppedAudioPacketCount = 0
        jitterQueuedFrameCount = 0
        resetAudioDebugCounters()
        activeGroupID = disconnectingGroupID
        markMembers(.offline)
        activeGroupID = nil
    }
}
