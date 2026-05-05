import AVFoundation
import Codec
import CryptoKit
import Foundation
import Logging
import OSLog
import RTC
import SessionManager
import VADGate

extension IntercomViewModel {
    var audioSessionModeProfile: AudioSessionProfile {
        audioSessionProfile.settingsModeProfile
    }

    var isSpeakerOutputEnabled: Bool {
        audioSessionProfile.defaultToSpeaker || selectedOutputPort == .speaker
    }

    var isSessionEchoCancellationEnabled: Bool {
        guard audioSessionModeProfile == .standard else { return false }
        return audioSessionProfile.prefersEchoCancelledInput || isSpeakerOutputEnabled
    }

    var canToggleSessionEchoCancellation: Bool {
        audioSessionModeProfile == .standard && !isSpeakerOutputEnabled
    }

    func setAudioSessionProfile(_ profile: AudioSessionProfile) {
        audioSessionProfile = profile
        saveAppSettings()
        guard configureAudioSession(active: isAudioReady) else { return }
        audioErrorMessage = nil
        AppLoggers.settings.info(
            "settings.audio_session.changed",
            metadata: .event("settings.audio_session.changed", [
                "profile": "\(profile.rawValue)"
            ])
        )
    }

    func setAudioSessionModeProfile(_ profile: AudioSessionProfile) {
        let previousOutputPort = selectedOutputPort
        let keepsEchoCancellation = isSessionEchoCancellationEnabled
        let keepsSpeakerOutput = isSpeakerOutputEnabled
        switch profile.settingsModeProfile {
        case .standard:
            audioSessionProfile = (keepsEchoCancellation || keepsSpeakerOutput) ? .echoCancelledInput : .standard
        case .voiceChat:
            audioSessionProfile = .voiceChat
        case .speakerDefault, .echoCancelledInput:
            audioSessionProfile = .standard
        }
        if keepsSpeakerOutput {
            selectedOutputPort = .speaker
        }
        saveAppSettings()
        guard configureAudioSession(active: isAudioReady) else { return }
        if selectedOutputPort != previousOutputPort {
            refreshOutputRendererIfNeeded()
        }
        audioErrorMessage = nil
        AppLoggers.settings.info(
            "settings.audio_session.changed",
            metadata: .event("settings.audio_session.changed", [
                "profile": "\(audioSessionProfile.rawValue)",
                "speaker": "\(isSpeakerOutputEnabled)"
            ])
        )
    }

    func setSpeakerOutputEnabled(_ enabled: Bool) {
        let previousOutputPort = selectedOutputPort
        if audioSessionModeProfile == .standard && enabled {
            audioSessionProfile = .echoCancelledInput
        } else if audioSessionProfile == .speakerDefault {
            audioSessionProfile = .echoCancelledInput
        }
        selectedOutputPort = enabled ? .speaker : .systemDefault
        saveAppSettings()
        guard configureAudioSession(active: isAudioReady) else { return }
        if selectedOutputPort != previousOutputPort {
            refreshOutputRendererIfNeeded()
        }
        audioErrorMessage = nil
        AppLoggers.settings.info(
            "settings.audio_speaker.changed",
            metadata: .event("settings.audio_speaker.changed", [
                "enabled": "\(enabled)",
                "profile": "\(audioSessionProfile.rawValue)"
            ])
        )
    }

    func setSessionEchoCancellationEnabled(_ enabled: Bool) {
        guard audioSessionModeProfile == .standard else { return }
        audioSessionProfile = enabled || isSpeakerOutputEnabled ? .echoCancelledInput : .standard
        saveAppSettings()
        guard configureAudioSession(active: isAudioReady) else { return }
        audioErrorMessage = nil
        AppLoggers.settings.info(
            "settings.echo_cancellation.changed",
            metadata: .event("settings.echo_cancellation.changed", [
                "enabled": "\(isSessionEchoCancellationEnabled)",
                "speaker": "\(isSpeakerOutputEnabled)"
            ])
        )
    }

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
        preferredTransmitCodec = codec
        callSession.setPreferredAudioCodec(codec)
        setLocalActiveCodec(selectedTransmitCodec)
        saveAppSettings()
        AppLoggers.settings.info(
            "settings.codec.changed",
            metadata: .event("settings.codec.changed", [
                "codec": "\(codec.rawValue)",
                "selectedCodec": "\(selectedTransmitCodec.rawValue)"
            ])
        )
        logCodecFallbackIfNeeded()
        broadcastMetadataKeepalive()
    }

    func setAACELDv2BitRate(_ bitRate: Int) {
        aacELDv2BitRate = Codec.AACELDv2Options(bitRate: bitRate).bitRate
        callSession.setAudioCodecOptions(aacELDv2BitRate: aacELDv2BitRate, opusBitRate: opusBitRate)
        saveAppSettings()
        AppLoggers.settings.info(
            "settings.codec.bitrate_changed",
            metadata: .event("settings.codec.bitrate_changed", [
                "codec": "\(AudioCodecIdentifier.mpeg4AACELDv2.rawValue)",
                "bitRate": "\(aacELDv2BitRate)"
            ])
        )
    }

    func setOpusBitRate(_ bitRate: Int) {
        opusBitRate = Codec.OpusOptions(bitRate: bitRate).bitRate
        callSession.setAudioCodecOptions(aacELDv2BitRate: aacELDv2BitRate, opusBitRate: opusBitRate)
        saveAppSettings()
        AppLoggers.settings.info(
            "settings.codec.bitrate_changed",
            metadata: .event("settings.codec.bitrate_changed", [
                "codec": "\(AudioCodecIdentifier.opus.rawValue)",
                "bitRate": "\(opusBitRate)"
            ])
        )
    }

    func setVADSensitivity(_ sensitivity: VoiceActivitySensitivity) {
        vadSensitivity = sensitivity
        audioTransmissionController.applyVADSensitivity(sensitivity)
        latestVADAnalysis = nil
        saveAppSettings()
        AppLoggers.settings.info(
            "settings.vad.changed",
            metadata: .event("settings.vad.changed", ["preset": "\(sensitivity.rawValue)"])
        )
    }

    func setMasterOutputVolume(_ volume: Float) {
        masterOutputVolume = min(2, max(0, volume))
    }

    func setSoundIsolationEnabled(_ enabled: Bool) {
        isSoundIsolationEnabled = enabled
        AppLoggers.settings.info(
            "settings.sound_isolation.changed",
            metadata: .event("settings.sound_isolation.changed", [
                "enabled": "\(enabled)"
            ])
        )
    }

    func setInputPort(_ port: AudioPortInfo) {
        selectedInputPort = port
        guard configureAudioSession(active: isAudioReady) else { return }
        audioErrorMessage = nil
        AppLoggers.settings.info(
            "settings.audio_device.changed",
            metadata: .event("settings.audio_device.changed", [
                "direction": "input",
                "selection": "\(port.id)"
            ])
        )
    }

    func setOutputPort(_ port: AudioPortInfo) {
        let previousOutputPort = selectedOutputPort
        selectedOutputPort = port
        guard configureAudioSession(active: isAudioReady) else { return }
        if selectedOutputPort != previousOutputPort {
            refreshOutputRendererIfNeeded()
        }
        audioErrorMessage = nil
        AppLoggers.settings.info(
            "settings.audio_device.changed",
            metadata: .event("settings.audio_device.changed", [
                "direction": "output",
                "selection": "\(port.id)"
            ])
        )
    }

    func setDuckOthersEnabled(_ enabled: Bool) {
        isDuckOthersEnabled = enabled
        refreshOtherAudioDuckingState()
        audioErrorMessage = nil
        AppLoggers.settings.info(
            "settings.ducking.changed",
            metadata: .event("settings.ducking.changed", [
                "enabled": "\(enabled)"
            ])
        )
    }

    func toggleOutputMute() {
        isOutputMuted.toggle()
        callSession.setOutputMute(isOutputMuted)
    }

    func resetAllSettings() {
        setInputPort(.systemDefault)
        setOutputPort(.systemDefault)
        setAudioSessionProfile(Self.defaultAudioSessionProfile)
        setDuckOthersEnabled(Self.defaultDuckOthersEnabled)
        setVADSensitivity(Self.defaultVADSensitivity)
        setSoundIsolationEnabled(Self.defaultSoundIsolationEnabled)
        setPreferredTransmitCodec(Self.defaultTransmitCodec)
        setAACELDv2BitRate(Self.defaultAACELDv2BitRate)
        setOpusBitRate(Self.defaultOpusBitRate)
        setMasterOutputVolume(1)
        isOutputMuted = false
        callSession.setOutputMute(false)
        let operationID = UUID().uuidString
        AppLoggers.settings.notice(
            "settings.reset",
            metadata: .event("settings.reset", [
                "operationID": "\(operationID)"
            ])
        )
    }

    private func saveAppSettings() {
        appSettingsStore.save(AppSettings(
            audioSessionProfile: audioSessionProfile,
            vadSensitivity: vadSensitivity,
            preferredTransmitCodec: preferredTransmitCodec,
            aacELDv2BitRate: aacELDv2BitRate,
            opusBitRate: opusBitRate
        ))
    }

    private func logCodecFallbackIfNeeded() {
        guard preferredTransmitCodec != selectedTransmitCodec else { return }
        AppLoggers.audio.notice(
            "audio.codec.fallback",
            metadata: .event("audio.codec.fallback", [
                "requestedCodec": "\(preferredTransmitCodec.rawValue)",
                "selectedCodec": "\(selectedTransmitCodec.rawValue)",
                "reason": "unavailable_or_route_unsupported"
            ])
        )
    }
}
