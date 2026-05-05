import AVFoundation
import Codec
import CryptoKit
import Foundation
import OSLog
import RTC
import SessionManager
import VADGate

extension IntercomViewModel {
    func resetAudioDebugCounters() {
        sentVoicePacketCount = 0
        receivedVoicePacketCount = 0
        playedAudioFrameCount = 0
        lastScheduledOutputRMS = 0
        lastScheduledOutputPeakRMS = 0
        scheduledOutputBatchCount = 0
        scheduledOutputFrameCount = 0
        lastReceivedAudioAt = nil
        lastAudibleReceivedAudioAt = nil
        droppedAudioPacketCount = 0
        jitterQueuedFrameCount = 0
        playbackOutputPeakWindow = VoicePeakWindow()
        transmitFallbackCount = 0
        lastTransmitFallbackSummary = nil
    }

    func refreshOtherAudioDuckingState(now: TimeInterval = Date().timeIntervalSince1970) {
        setOtherAudioDuckingActive(shouldApplyOtherAudioDucking(now: now))
    }

    func shouldApplyOtherAudioDucking(now: TimeInterval) -> Bool {
        guard isDuckOthersEnabled, isAudioReady, audioCheckPhase == .idle else { return false }
        return hasRecentReceivedAudio(now: now)
    }

    func hasRecentReceivedAudio(now: TimeInterval) -> Bool {
        guard let lastAudibleReceivedAudioAt else { return false }
        return now - lastAudibleReceivedAudioAt <= Self.otherAudioDuckingHoldDuration
    }

    func setOtherAudioDuckingActive(_ isActive: Bool) {
        guard isOtherAudioDuckingActiveInternal != isActive else { return }
        isOtherAudioDuckingActiveInternal = isActive
        audioInputMonitor.setOtherAudioDuckingEnabled(isActive)
    }

    func hasAudibleScheduledOutput(for frames: [JitterBufferedAudioFrame]) -> Bool {
        frames.contains { frame in
            guard !frame.samples.isEmpty else { return false }
            return AudioLevelMeter.rmsLevel(samples: frame.samples) > VoiceActivityDetector.minThreshold
        }
    }

    func applyOutputGain(to frames: [JitterBufferedAudioFrame]) -> [JitterBufferedAudioFrame] {
        frames.map { frame in
            let gain = isOutputMuted ? 0 : masterOutputVolume * remoteOutputVolume(for: frame.peerID)
            return JitterBufferedAudioFrame(
                peerID: frame.peerID,
                streamID: frame.streamID,
                sequenceNumber: frame.sequenceNumber,
                frameID: frame.frameID,
                samples: frame.samples.map { softClippedAudioSample($0 * gain) }
            )
        }
    }

    func clampedMasterOutputVolume(_ value: Float) -> Float {
        min(Self.maximumMasterOutputVolume, max(0, value))
    }

    func clampedAudioGain(_ value: Float) -> Float {
        min(1, max(0, value))
    }

    func softClippedAudioSample(_ value: Float) -> Float {
        let threshold: Float = 0.9
        let absVal = fabsf(value)
        if absVal <= threshold { return value }
        let headroom: Float = 1 - threshold
        let overshoot = (absVal - threshold) / headroom
        return copysignf(threshold + headroom * (1 - expf(-overshoot)), value)
    }
}
