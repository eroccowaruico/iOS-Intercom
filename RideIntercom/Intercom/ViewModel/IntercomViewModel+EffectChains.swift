import Foundation

extension IntercomViewModel {
    var transmitEffectChainSnapshot: AudioEffectChainSnapshot {
        AudioEffectChainSnapshot(
            id: "tx-bus",
            stages: [
                soundIsolationStageSnapshot(
                    enabled: isSoundIsolationEnabled,
                    activeLabel: "SI",
                    bypassedLabel: "SI Off"
                ),
                vadGateStageSnapshot(),
                dynamicsProcessorStageSnapshot(),
                peakLimiterStageSnapshot(detailWhenActive: "Peak guard ready")
            ]
        )
    }

    func receivePeerEffectChainSnapshot(peerID: String) -> AudioEffectChainSnapshot {
        AudioEffectChainSnapshot(
            id: "rx-peer-\(peerID)",
            stages: [
                soundIsolationStageSnapshot(
                    enabled: isRemoteSoundIsolationEnabled(peerID: peerID),
                    activeLabel: "SI",
                    bypassedLabel: "SI Off"
                )
            ]
        )
    }

    var receiveMasterEffectChainSnapshot: AudioEffectChainSnapshot {
        AudioEffectChainSnapshot(
            id: "rx-master",
            stages: [
                soundIsolationStageSnapshot(
                    enabled: receiveMasterSoundIsolationEnabled,
                    activeLabel: "SI",
                    bypassedLabel: "SI Off"
                ),
                peakLimiterStageSnapshot(detailWhenActive: "Final peak guard ready")
            ]
        )
    }

    private func soundIsolationStageSnapshot(
        enabled: Bool,
        activeLabel: String,
        bypassedLabel: String
    ) -> AudioEffectStageSnapshot {
        let state: AudioEffectStageRuntimeState
        let detail: String
        let shortLabel: String

        if !isAudioReady {
            state = .idle
            detail = "Idle"
            shortLabel = enabled ? activeLabel : bypassedLabel
        } else if enabled && !supportsSoundIsolation {
            state = .unavailable
            detail = "Unavailable"
            shortLabel = "SI N/A"
        } else if enabled {
            state = .active
            detail = "Enabled"
            shortLabel = activeLabel
        } else {
            state = .bypassed
            detail = "Bypassed"
            shortLabel = bypassedLabel
        }

        return AudioEffectStageSnapshot(
            id: "sound-isolation",
            package: "SoundIsolation",
            name: "SoundIsolation",
            shortLabel: shortLabel,
            detail: detail,
            state: state
        )
    }

    private func vadGateStageSnapshot() -> AudioEffectStageSnapshot {
        let state: AudioEffectStageRuntimeState
        let shortLabel: String
        let detail: String

        if !isAudioReady {
            state = .idle
            shortLabel = "VAD"
            detail = "Idle"
        } else if isMuted {
            state = .waiting
            shortLabel = "VAD Muted"
            detail = "Input muted"
        } else {
            state = isVoiceActive ? .active : .waiting
            shortLabel = isVoiceActive ? "VAD Speech" : "VAD Silent"
            detail = "\(vadSensitivity.label) / \(vadAnalysisSummary)"
        }

        return AudioEffectStageSnapshot(
            id: "vad-gate",
            package: "VADGate",
            name: "VADGate",
            shortLabel: shortLabel,
            detail: detail,
            state: state
        )
    }

    private func dynamicsProcessorStageSnapshot() -> AudioEffectStageSnapshot {
        AudioEffectStageSnapshot(
            id: "dynamics-processor",
            package: "DynamicsProcessor",
            name: "Dynamics",
            shortLabel: "Dyn",
            detail: isAudioReady ? "Leveling ready" : "Idle",
            state: isAudioReady ? .active : .idle
        )
    }

    private func peakLimiterStageSnapshot(detailWhenActive: String) -> AudioEffectStageSnapshot {
        AudioEffectStageSnapshot(
            id: "peak-limiter",
            package: "PeakLimiter",
            name: "Peak Limit",
            shortLabel: "Limit",
            detail: isAudioReady ? detailWhenActive : "Idle",
            state: isAudioReady ? .active : .idle
        )
    }
}
