import CryptoKit
import AVFoundation
import Codec
import Foundation
import Observation
import OSLog
import RTC
import SessionManager
import VADGate

struct AudioTransmissionController {
    static let defaultVoiceActivityThreshold = VoiceActivityDetector.defaultThreshold

    private struct CapturedFrame {
        let frameID: Int
        let samples: [Float]
    }

    private var detector: VoiceActivityDetector
    private let preRollLimit: Int
    private let keepaliveIntervalFrames: Int
    private var preRoll: [CapturedFrame] = []
    private var framesSinceKeepalive = 0
    private var wasSendingVoice = false

    init(
        detector: VoiceActivityDetector = VoiceActivityDetector(threshold: Self.defaultVoiceActivityThreshold),
        preRollLimit: Int = 20,
        keepaliveIntervalFrames: Int = 50
    ) {
        self.detector = detector
        self.preRollLimit = preRollLimit
        self.keepaliveIntervalFrames = keepaliveIntervalFrames
    }

    mutating func process(frameID: Int, level: Float, samples: [Float] = []) -> [OutboundAudioPacket] {
        let state = detector.process(level: level)
        var packets: [OutboundAudioPacket] = []

        if state == .talking || state == .release {
            if !wasSendingVoice {
                packets.append(contentsOf: preRoll.map { .voice(frameID: $0.frameID, samples: $0.samples) })
            }
            packets.append(.voice(frameID: frameID, samples: samples))
            framesSinceKeepalive = 0
            wasSendingVoice = true
        } else {
            appendToPreRoll(frameID: frameID, samples: samples)
            framesSinceKeepalive += 1
            wasSendingVoice = false

            if framesSinceKeepalive >= keepaliveIntervalFrames {
                packets.append(.keepalive)
                framesSinceKeepalive = 0
            }
        }

        return packets
    }

    mutating func setVoiceActivityThreshold(_ threshold: Float) {
        detector.setThreshold(threshold)
    }

    private mutating func appendToPreRoll(frameID: Int, samples: [Float]) {
        preRoll.append(CapturedFrame(frameID: frameID, samples: samples))
        if preRoll.count > preRollLimit {
            preRoll.removeFirst(preRoll.count - preRollLimit)
        }
    }
}
