import AVFoundation
import AVFAudio
import Codec
import CryptoKit
import Foundation
import OSLog
import RTC
import SessionManager
import VADGate

struct AudioInputPipeline {
    let capture: SessionManager.AudioInputStreamCapture
    let voiceProcessingManager: SessionManager.AudioInputVoiceProcessingManager?
}

extension IntercomViewModel {
    static func makeForCurrentProcess() -> IntercomViewModel {
        let localMemberIdentityStore = UserDefaultsLocalMemberIdentityStore()
        return IntercomViewModel(
            callSession: makeDefaultCallSession(localMemberIdentityStore: localMemberIdentityStore),
            credentialStore: KeychainGroupCredentialStore(),
            groupStore: UserDefaultsGroupStore(),
            localMemberIdentityStore: localMemberIdentityStore
        )
    }

    static func makeDefaultCallSession(localMemberIdentityStore: any LocalMemberIdentityStoring) -> CallSession {
        RideIntercomCallSessionAdapter(memberID: localMemberIdentityStore.loadOrCreate().memberID)
    }

    static func makeDefaultAudioInputPipeline() -> AudioInputPipeline {
        let engine = AVAudioEngine()
        let voiceProcessingManager = SessionManager.AudioInputVoiceProcessingManager(
            backend: SessionManager.SystemAudioInputVoiceProcessingBackend(inputNode: engine.inputNode)
        )
        let backend = SessionManager.SystemAudioInputStreamBackend(
            engine: engine,
            voiceProcessingManager: voiceProcessingManager
        )
        return AudioInputPipeline(
            capture: SessionManager.AudioInputStreamCapture(
                configuration: .intercom(voiceProcessing: defaultVoiceProcessingConfiguration()),
                backend: backend
            ),
            voiceProcessingManager: voiceProcessingManager
        )
    }

    static func makeDefaultAudioOutputRenderer() -> SessionManager.AudioOutputStreamRenderer {
        SessionManager.AudioOutputStreamRenderer(configuration: .intercom)
    }

    static func defaultVoiceProcessingConfiguration() -> SessionManager.AudioInputVoiceProcessingConfiguration {
        SessionManager.AudioInputVoiceProcessingConfiguration(
            soundIsolationEnabled: defaultSoundIsolationEnabled,
            otherAudioDuckingEnabled: false,
            duckingLevel: .minimum,
            inputMuted: false
        )
    }

    static func defaultAudioSessionSnapshot() -> SessionManager.AudioSessionSnapshot {
        SessionManager.AudioSessionSnapshot(
            isActive: false,
            availableInputs: [.systemDefaultInput],
            availableOutputs: [.systemDefaultOutput],
            currentInput: .systemDefaultInput,
            currentOutput: .systemDefaultOutput
        )
    }
}
