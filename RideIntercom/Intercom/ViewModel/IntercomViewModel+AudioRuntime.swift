import Foundation
import SessionManager

extension IntercomViewModel {
    func expireRemoteTalkers(now: TimeInterval = Date().timeIntervalSince1970) {
        for (peerID, lastVoiceAt) in remoteVoiceReceivedAt where now - lastVoiceAt >= remoteTalkerTimeout {
            setRemotePeer(peerID, isTalking: false)
            remoteVoiceReceivedAt.removeValue(forKey: peerID)
        }
    }

    func handleCallTick(now: TimeInterval) {
        expireRemoteTalkers(now: now)
        refreshOtherAudioDuckingState(now: now)
    }

    func handleAudioStreamRuntimeEvent(_ event: SessionManager.AudioStreamRuntimeEvent) {
        switch event {
        case .inputFrame(let frame):
            handleMicrophoneFrame(frame)
        case .operation(let report):
            recordAudioStreamReport(report)
        case .outputFrameScheduled:
            break
        }
    }

    func recordAudioStreamReport(_ report: SessionManager.AudioStreamOperationReport) {
        switch report.snapshot.direction {
        case .input:
            if case .updateInputVoiceProcessing = report.operation {
                lastVoiceProcessingOperationReport = report
            } else {
                lastInputStreamOperationReport = report
            }
        case .output:
            lastOutputStreamOperationReport = report
        }
    }

    func handleMicrophoneFrame(_ frame: SessionManager.AudioStreamFrame) {
        processMicrophoneFrame(level: frame.level.rms, samples: frame.samples)
    }

    func processMicrophoneFrame(level: Float, samples: [Float]) {
        processAudioCheckInput(level: level, samples: samples)

        guard isAudioReady else { return }

        guard !isMuted else {
            setLocalVoiceLevel(0)
            setVoiceActive(false)
            return
        }

        let frameID = nextAudioFrameID
        nextAudioFrameID += 1

        setLocalVoiceLevel(level)
        let packets = audioTransmissionController.process(frameID: frameID, level: level, samples: samples)
        latestVADAnalysis = audioTransmissionController.lastAnalysis
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
