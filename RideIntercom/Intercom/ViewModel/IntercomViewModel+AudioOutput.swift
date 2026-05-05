import Foundation
import RTC
import SessionManager

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
        applyCurrentVoiceProcessingConfiguration()
    }

    func scheduleOutputFrame(peerID: String, frame: RTC.AudioFrame, receivedAt: TimeInterval) {
        guard !isOutputMuted else {
            lastScheduledOutputRMS = 0
            lastScheduledOutputPeakRMS = playbackOutputPeakWindow.record(0)
            return
        }

        let level = AudioLevelMeter.rmsLevel(samples: frame.samples)
        lastScheduledOutputRMS = level
        lastScheduledOutputPeakRMS = playbackOutputPeakWindow.record(level)
        scheduledOutputBatchCount += 1
        scheduledOutputFrameCount += 1
        playedAudioFrameCount += 1
        markPlayedAudioFrame(peerID: peerID)
        _ = audioOutputRenderer.schedule(SessionManager.AudioStreamFrame(
            sequenceNumber: frame.sequenceNumber,
            format: .intercom,
            capturedAt: receivedAt,
            samples: frame.samples
        ))
        if level > VoiceActivityDetector.minThreshold {
            lastAudibleReceivedAudioAt = receivedAt
        }
    }
}
