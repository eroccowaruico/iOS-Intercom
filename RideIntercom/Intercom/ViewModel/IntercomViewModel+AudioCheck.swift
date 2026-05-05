import AVFoundation
import Codec
import CryptoKit
import Foundation
import OSLog
import RTC
import SessionManager
import VADGate

extension IntercomViewModel {
    func startAudioCheck(recordDuration: Duration = .seconds(5), playbackDuration: Duration = .seconds(5)) {
        guard audioCheckPhase != .recording, audioCheckPhase != .playing else { return }

        audioCheckTask?.cancel()
        resetAudioCheckMeters()
        audioCheckRecordedSamples = []
        audioCheckPhase = .recording
        audioCheckStatusMessage = "Recording microphone for 5 seconds"
        audioCheckOwnsAudioPipeline = !isAudioReady

        do {
            if audioCheckOwnsAudioPipeline {
                try audioSessionManager.configureForAudioCheck()
            }
            try audioInputMonitor.start()
            try audioFramePlayer.start()
        } catch {
            audioCheckPhase = .failed
            audioCheckStatusMessage = audioSetupMessage(for: error)
            if audioCheckOwnsAudioPipeline {
                audioInputMonitor.stop()
                audioFramePlayer.stop()
                try? audioSessionManager.deactivate()
            }
            return
        }

        audioCheckTask = Task { [weak self] in
            try? await Task.sleep(for: recordDuration)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.finishAudioCheckRecording(playbackDuration: playbackDuration)
            }
        }
    }

    func processAudioCheckInput(level: Float, samples: [Float]) {
        guard audioCheckPhase == .recording else { return }

        let clampedLevel = min(1, max(0, level))
        audioCheckInputLevel = clampedLevel
        audioCheckInputPeakLevel = audioCheckInputPeakWindow.record(clampedLevel)
        audioCheckRecordedSamples.append(contentsOf: samples)
    }

    func finishAudioCheckRecording(playbackDuration: Duration) {
        guard audioCheckPhase == .recording else { return }

        let recordedSamples = audioCheckRecordedSamples
        guard !recordedSamples.isEmpty else {
            audioCheckPhase = .failed
            audioCheckStatusMessage = "No microphone samples captured"
            stopAudioCheckOwnedPipeline()
            return
        }

        let playbackCodec: AudioCodecIdentifier = .pcm16
        let playbackSamples = makeAudioCheckPlaybackSamples(from: recordedSamples)

        let outputLevel = AudioLevelMeter.rmsLevel(samples: playbackSamples)
        audioCheckOutputLevel = min(1, max(0, outputLevel))
        audioCheckOutputPeakLevel = audioCheckOutputPeakWindow.record(audioCheckOutputLevel)
        audioCheckPhase = .playing
        audioCheckStatusMessage = "Playing recorded audio for 5 seconds (\(audioCodecDisplayName(playbackCodec)))"
        audioFramePlayer.play(JitterBufferedAudioFrame(
            peerID: "audio-check",
            streamID: UUID(),
            sequenceNumber: 1,
            frameID: 1,
            samples: playbackSamples
        ))

        audioCheckTask?.cancel()
        audioCheckTask = Task { [weak self] in
            try? await Task.sleep(for: playbackDuration)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.completeAudioCheckPlayback()
            }
        }
    }

    func completeAudioCheckPlayback() {
        guard audioCheckPhase == .playing else { return }

        audioCheckPhase = .completed
        audioCheckStatusMessage = "Audio check complete"
        audioCheckOutputLevel = 0
        stopAudioCheckOwnedPipeline()
    }

    func stopAudioCheckOwnedPipeline() {
        guard audioCheckOwnsAudioPipeline else { return }

        audioInputMonitor.stop()
        audioFramePlayer.stop()
        try? audioSessionManager.deactivate()
        audioCheckOwnsAudioPipeline = false
    }

    func resetAudioCheckMeters() {
        audioCheckInputLevel = 0
        audioCheckInputPeakLevel = 0
        audioCheckOutputLevel = 0
        audioCheckOutputPeakLevel = 0
        audioCheckInputPeakWindow = VoicePeakWindow()
        audioCheckOutputPeakWindow = VoicePeakWindow()
    }

    func makeAudioCheckPlaybackSamples(from samples: [Float]) -> [Float] {
        guard let packet = try? EncodedVoicePacket.make(frameID: 1, samples: samples) else {
            return samples
        }

        guard let decodedSamples = try? packet.decodeSamples(), !decodedSamples.isEmpty else {
            return samples
        }
        return decodedSamples
    }

    func audioCodecDisplayName(_ codec: AudioCodecIdentifier) -> String {
        if codec == .pcm16 { return "PCM 16-bit" }
        if codec == .heAACv2 { return "HE-AAC v2 VBR" }
        if codec == .opus { return "Opus" }
        return codec.rawValue
    }
}
