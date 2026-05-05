import Foundation
import Logging
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
        guard isDuckOthersEnabled,
              isAudioReady,
              audioCheckPhase == .idle,
              !isOutputMuted,
              masterOutputVolume > 0 else { return false }
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
        guard !isOutputMuted, masterOutputVolume > 0 else {
            lastScheduledOutputRMS = 0
            lastScheduledOutputPeakRMS = playbackOutputPeakWindow.record(0)
            return
        }

        let outputSamples = frame.samples.map { softClip($0 * masterOutputVolume) }
        let level = AudioLevelMeter.rmsLevel(samples: outputSamples)
        lastScheduledOutputRMS = level
        lastScheduledOutputPeakRMS = playbackOutputPeakWindow.record(level)
        scheduledOutputBatchCount += 1
        scheduledOutputFrameCount += 1
        playedAudioFrameCount += 1
        markPlayedAudioFrame(peerID: peerID)
        let report = audioOutputRenderer.schedule(SessionManager.AudioStreamFrame(
            sequenceNumber: frame.sequenceNumber,
            format: .intercom,
            capturedAt: receivedAt,
            samples: outputSamples
        ))
        lastOutputStreamOperationReport = report
        if !report.result.isContinuable {
            audioErrorMessage = "Audio output failed"
            AppLoggers.audio.warning(
                "audio.output.schedule_failed",
                metadata: .event("audio.output.schedule_failed", [
                    "errorType": "\(report.result)",
                    "isRecoverable": "true"
                ])
            )
        }
        if level > Self.audibleOutputLevelThreshold {
            lastAudibleReceivedAudioAt = receivedAt
        }
    }

    private func softClip(_ sample: Float) -> Float {
        max(-1, min(1, sample))
    }
}

private extension SessionManager.AudioStreamOperationResult {
    var isContinuable: Bool {
        switch self {
        case .applied, .ignored(_):
            true
        case .failed(_):
            false
        }
    }
}
