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
        audioInputMonitor.setInputMuted(isMuted)

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

    func setHEAACv2Quality(_ quality: HEAACv2Quality) {
        heAACv2Quality = .medium
        broadcastMetadataKeepalive()
    }

    func setVoiceActivityDetectionThreshold(_ value: Float) {
        let clamped = min(VoiceActivityDetector.maxThreshold, max(VoiceActivityDetector.minThreshold, value))
        voiceActivityDetectionThreshold = clamped
        audioTransmissionController.setVoiceActivityThreshold(clamped)
    }

    func setSoundIsolationEnabled(_ enabled: Bool) {
        guard audioInputMonitor.supportsSoundIsolation else {
            isSoundIsolationEnabled = false
            return
        }
        audioInputMonitor.setSoundIsolationEnabled(enabled)
        isSoundIsolationEnabled = audioInputMonitor.isSoundIsolationEnabled
    }

    func setInputPort(_ port: AudioPortInfo) {
        do {
            try audioSessionManager.setInputPort(port)
            selectedInputPort = audioSessionManager.selectedInputPort
            audioErrorMessage = nil
        } catch {
            audioErrorMessage = "Audio input device change failed"
        }
    }

    func setOutputPort(_ port: AudioPortInfo) {
        do {
            let previousOutputPort = selectedOutputPort
            try audioSessionManager.setOutputPort(port)
            selectedOutputPort = audioSessionManager.selectedOutputPort
            if selectedOutputPort != previousOutputPort {
                try refreshOutputRendererIfNeeded()
            }
            audioErrorMessage = nil
        } catch {
            audioErrorMessage = "Audio output device change failed"
        }
    }

    func setDuckOthersEnabled(_ enabled: Bool) {
        do {
            try audioSessionManager.setDuckOthersEnabled(enabled)
            isDuckOthersEnabled = audioSessionManager.isDuckOthersEnabled
            refreshOtherAudioDuckingState()
            audioErrorMessage = nil
        } catch {
            audioErrorMessage = "Audio session ducking change failed"
        }
    }

    func setMasterOutputVolume(_ value: Float) {
        masterOutputVolume = clampedMasterOutputVolume(value)
    }

    func toggleOutputMute() {
        isOutputMuted.toggle()
    }

    func setRemoteOutputVolume(peerID: String, value: Float) {
        remoteOutputVolumes[peerID] = clampedAudioGain(value)
    }

    func remoteOutputVolume(for peerID: String) -> Float {
        remoteOutputVolumes[peerID] ?? 1
    }

    func resetAllSettings() {
        setInputPort(.systemDefault)
        setOutputPort(.systemDefault)
        setDuckOthersEnabled(false)
        setVoiceActivityDetectionThreshold(AudioTransmissionController.defaultVoiceActivityThreshold)
        setSoundIsolationEnabled(Self.defaultSoundIsolationEnabled)
        setPreferredTransmitCodec(Self.defaultTransmitCodec)
        setHEAACv2Quality(Self.defaultHEAACv2Quality)
        setMasterOutputVolume(Self.normalMasterOutputVolume)
        isOutputMuted = false
        remoteOutputVolumes = [:]
    }
}
