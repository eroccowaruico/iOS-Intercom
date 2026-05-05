import AVFoundation
import Codec
import CryptoKit
import Foundation
import OSLog
import RTC
import SessionManager
import VADGate

extension IntercomViewModel {
    func expireRemoteTalkers(now: TimeInterval = Date().timeIntervalSince1970) {
        for (peerID, lastVoiceAt) in remoteVoiceReceivedAt where now - lastVoiceAt >= remoteTalkerTimeout {
            setRemotePeer(peerID, isTalking: false)
            remoteVoiceReceivedAt.removeValue(forKey: peerID)
        }
    }

    func handleCallTick(now: TimeInterval) {
        expireRemoteTalkers(now: now)
        drainJitterBuffer(now: now)
        refreshOtherAudioDuckingState(now: now)
    }

    func drainJitterBuffer(now: TimeInterval) {
        let readyFrames = jitterBuffer.drainReadyFrames(now: now)
        playedAudioFrameCount += readyFrames.count
        droppedAudioPacketCount = jitterBuffer.droppedFrameCount
        jitterQueuedFrameCount = jitterBuffer.queuedFrameCount
        markPlayedAudioFrames(readyFrames)
        let outputFrames = applyOutputGain(to: readyFrames)
        let mixedOutput = AudioFrameMixer.mix(outputFrames)
        let outputLevel = AudioLevelMeter.rmsLevel(samples: mixedOutput)
        lastScheduledOutputRMS = outputLevel
        lastScheduledOutputPeakRMS = playbackOutputPeakWindow.record(outputLevel)
        if !outputFrames.isEmpty {
            scheduledOutputBatchCount += 1
            scheduledOutputFrameCount += outputFrames.count
        }
        audioFramePlayer.play(outputFrames)
        if hasAudibleScheduledOutput(for: outputFrames) {
            lastAudibleReceivedAudioAt = now
            refreshOtherAudioDuckingState(now: now)
        }
    }

    func handleMicrophoneLevel(_ level: Float) {
        processMicrophoneFrame(level: level, samples: [])
    }

    func handleMicrophoneSamples(_ samples: [Float]) {
        processMicrophoneFrame(level: AudioLevelMeter.rmsLevel(samples: samples), samples: samples)
    }

    func processMicrophoneFrame(level: Float, samples: [Float]) {
        processAudioCheckInput(level: level, samples: samples)

        guard !isMuted else {
            setLocalVoiceLevel(0)
            setVoiceActive(false)
            return
        }

        let frameID = nextAudioFrameID
        nextAudioFrameID += 1

        setLocalVoiceLevel(level)
        let packets = audioTransmissionController.process(frameID: frameID, level: level, samples: samples)
        for packet in packets {
            send(packet)
        }

        setVoiceActive(packets.contains { packet in
            if case .voice = packet {
                return true
            }
            return false
        })
    }
}
