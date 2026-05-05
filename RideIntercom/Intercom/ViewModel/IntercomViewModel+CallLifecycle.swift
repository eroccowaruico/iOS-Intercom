import Foundation
import SessionManager

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

        callSession.startMedia()
        guard configureAudioSession(active: true),
              startInputCapture(),
              startOutputRenderer() else {
            callSession.stopMedia()
            isAudioReady = false
            return false
        }

        applyCurrentVoiceProcessingConfiguration()
        callTicker.start()
        isAudioReady = true
        refreshOtherAudioDuckingState()
        audioErrorMessage = nil
        return true
    }

    func stopAudioPipeline(deactivateSession: Bool = false) {
        setOtherAudioDuckingActive(false)
        callSession.stopMedia()
        _ = audioInputCapture.stop()
        _ = audioOutputRenderer.stop()
        callTicker.stop()
        if deactivateSession {
            _ = try? audioSessionManager.setActive(false)
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

    func configureAudioSession(active: Bool) -> Bool {
        do {
            let report = try audioSessionManager.configure(makeAudioSessionConfiguration())
            if let snapshot = report.snapshot {
                applyAudioSessionSnapshot(snapshot)
            }
            if active {
                let activeReport = try audioSessionManager.setActive(true)
                guard activeReport.result.isContinuable else {
                    audioErrorMessage = "Audio session activation failed"
                    return false
                }
            }
            guard report.operations.allSatisfy(\.result.isContinuable) else {
                audioErrorMessage = "Audio session configuration failed"
                return false
            }
            return true
        } catch {
            audioErrorMessage = "Audio session configuration failed"
            return false
        }
    }

    func makeAudioSessionConfiguration() -> SessionManager.AudioSessionConfiguration {
        .intercom(
            prefersSpeakerOutput: selectedOutputPort == .speaker,
            preferredInput: selectedInputPort.sessionManagerInputSelection,
            preferredOutput: selectedOutputPort.sessionManagerOutputSelection
        )
    }

    func startInputCapture() -> Bool {
        let report = audioInputCapture.start()
        guard report.result.isContinuable else {
            audioErrorMessage = "Microphone capture failed"
            return false
        }
        return true
    }

    func startOutputRenderer() -> Bool {
        let report = audioOutputRenderer.start()
        guard report.result.isContinuable else {
            audioErrorMessage = "Audio output failed"
            return false
        }
        return true
    }

    func currentVoiceProcessingConfiguration() -> SessionManager.AudioInputVoiceProcessingConfiguration {
        SessionManager.AudioInputVoiceProcessingConfiguration(
            soundIsolationEnabled: isSoundIsolationEnabled,
            otherAudioDuckingEnabled: isOtherAudioDuckingActiveInternal,
            duckingLevel: .minimum,
            inputMuted: isMuted
        )
    }

    func applyCurrentVoiceProcessingConfiguration() {
        try? audioInputVoiceProcessingManager?.configure(currentVoiceProcessingConfiguration())
    }
}

private extension SessionManager.AudioSessionOperationResult {
    var isContinuable: Bool {
        switch self {
        case .applied, .ignored:
            true
        case .failed:
            false
        }
    }
}

private extension SessionManager.AudioStreamOperationResult {
    var isContinuable: Bool {
        switch self {
        case .applied, .ignored(.alreadyRunning):
            true
        case .ignored, .failed:
            false
        }
    }
}
