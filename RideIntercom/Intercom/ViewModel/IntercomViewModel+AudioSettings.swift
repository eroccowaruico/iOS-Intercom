import AVFoundation
import Codec
import CryptoKit
import Foundation
import OSLog
import RTC
import SessionManager
import VADGate

extension IntercomViewModel {
    func toggleMute() {
        isMuted.toggle()
        applyCurrentVoiceProcessingConfiguration()
        callSession.setLocalMute(isMuted)

        withActiveGroup { group in
            guard !group.members.isEmpty else { return }
            group.members[0].isMuted = isMuted
            if isMuted {
                group.members[0].isTalking = false
                group.members[0].voiceLevel = 0
                group.members[0].voicePeakLevel = 0
            }
        }
        if isMuted {
            localVoicePeakWindow = VoicePeakWindow()
        }
        broadcastControl(.peerMuteState(isMuted: isMuted))
        broadcastMetadataKeepalive()
    }

    func setPreferredTransmitCodec(_ codec: AudioCodecIdentifier) {
        preferredTransmitCodec = AppAudioCodecBridge.resolvedPreferredCodec(codec, format: .intercomPacketAudio)
        callSession.setPreferredAudioCodec(preferredTransmitCodec)
        setLocalActiveCodec(preferredTransmitCodec)
        broadcastMetadataKeepalive()
    }

    func setVoiceActivityDetectionThreshold(_ value: Float) {
        let clamped = min(VoiceActivityDetector.maxThreshold, max(VoiceActivityDetector.minThreshold, value))
        voiceActivityDetectionThreshold = clamped
        audioTransmissionController.setVoiceActivityThreshold(clamped)
    }

    func setSoundIsolationEnabled(_ enabled: Bool) {
        isSoundIsolationEnabled = enabled
        applyCurrentVoiceProcessingConfiguration()
    }

    func setInputPort(_ port: AudioPortInfo) {
        selectedInputPort = port
        guard configureAudioSession(active: isAudioReady) else { return }
        audioErrorMessage = nil
    }

    func setOutputPort(_ port: AudioPortInfo) {
        let previousOutputPort = selectedOutputPort
        selectedOutputPort = port
        guard configureAudioSession(active: isAudioReady) else { return }
        if selectedOutputPort != previousOutputPort {
            refreshOutputRendererIfNeeded()
        }
        audioErrorMessage = nil
    }

    func setDuckOthersEnabled(_ enabled: Bool) {
        isDuckOthersEnabled = enabled
        refreshOtherAudioDuckingState()
        audioErrorMessage = nil
    }

    func toggleOutputMute() {
        isOutputMuted.toggle()
        callSession.setOutputMute(isOutputMuted)
    }

    func resetAllSettings() {
        setInputPort(.systemDefault)
        setOutputPort(.systemDefault)
        setDuckOthersEnabled(false)
        setVoiceActivityDetectionThreshold(AudioTransmissionController.defaultVoiceActivityThreshold)
        setSoundIsolationEnabled(Self.defaultSoundIsolationEnabled)
        setPreferredTransmitCodec(Self.defaultTransmitCodec)
        isOutputMuted = false
        callSession.setOutputMute(false)
    }
}
