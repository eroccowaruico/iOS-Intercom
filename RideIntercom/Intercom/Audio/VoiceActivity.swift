import CryptoKit
import AVFoundation
import Codec
import Foundation
import Observation
import OSLog
import RTC
import SessionManager
import VADGate

enum VoiceActivityState: Equatable {
    case idle
    case attack
    case talking
    case release
}

struct VoiceActivityDetector {
    static let minThreshold: Float = 0.00025
    static let maxThreshold: Float = 0.12
    static let defaultThreshold: Float = 0.003

    private(set) var state: VoiceActivityState = .idle
    private var threshold: Float
    private let attackFrames: Int
    private let releaseFrames: Int
    private var speechFrames = 0
    private var silenceFrames = 0
    private var noiseFloor: Float = VoiceActivityDetector.minThreshold

    init(threshold: Float = VoiceActivityDetector.defaultThreshold, attackFrames: Int = 1, releaseFrames: Int = 40) {
        self.threshold = min(Self.maxThreshold, max(Self.minThreshold, threshold))
        self.attackFrames = attackFrames
        self.releaseFrames = releaseFrames
    }

    mutating func setThreshold(_ threshold: Float) {
        self.threshold = min(Self.maxThreshold, max(Self.minThreshold, threshold))
    }

    mutating func process(level: Float) -> VoiceActivityState {
        let clampedLevel = min(1, max(0, level))
        updateNoiseFloor(using: clampedLevel)

        let startMargin = max(threshold, noiseFloor * 0.6)
        let releaseMargin = max(threshold * 0.35, noiseFloor * 0.2)
        let startThreshold = min(Self.maxThreshold, max(Self.minThreshold, noiseFloor + startMargin))
        let releaseThreshold = min(Self.maxThreshold, max(Self.minThreshold, noiseFloor + releaseMargin))

        if clampedLevel >= startThreshold {
            speechFrames += 1
            silenceFrames = 0

            if speechFrames >= attackFrames {
                state = .talking
            } else {
                state = .attack
            }
        } else {
            speechFrames = 0

            switch state {
            case .talking, .release:
                if clampedLevel <= releaseThreshold {
                    silenceFrames += 1
                    state = silenceFrames >= releaseFrames ? .idle : .release
                } else {
                    silenceFrames = 0
                    state = .release
                }
            case .idle, .attack:
                silenceFrames = 0
                state = .idle
            }
        }

        return state
    }

    private mutating func updateNoiseFloor(using level: Float) {
        let floorTarget = min(level, 0.2)
        let smoothing: Float

        switch state {
        case .idle:
            smoothing = 0.04
        case .attack:
            smoothing = 0.015
        case .talking:
            smoothing = 0.002
        case .release:
            smoothing = 0.02
        }

        noiseFloor += (floorTarget - noiseFloor) * smoothing
        noiseFloor = min(0.2, max(0, noiseFloor))
    }
}

