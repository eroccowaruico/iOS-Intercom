import Foundation

public struct VADConfiguration: Sendable {
    public let energyThreshold: Float
    public let attackDuration: TimeInterval
    public let releaseDuration: TimeInterval
    public let preRollDuration: TimeInterval

    public init(
        energyThreshold: Float = 0.015,
        attackDuration: TimeInterval = 0.05,
        releaseDuration: TimeInterval = 0.3,
        preRollDuration: TimeInterval = 0.2
    ) {
        self.energyThreshold = energyThreshold
        self.attackDuration = attackDuration
        self.releaseDuration = releaseDuration
        self.preRollDuration = preRollDuration
    }
}

public enum VADState: Sendable, Equatable {
    case idle
    case attack
    case talking
    case release
}

public struct VADDecision: Sendable, Equatable {
    public let state: VADState
    public let shouldTransmit: Bool
    public let preRollFrames: [AudioFrame]
}

public final class VoiceActivityDetector {
    private let configuration: VADConfiguration
    private var state: VADState = .idle
    private var stateStart: Date = Date()
    private var preRollBuffer: [AudioFrame] = []
    private var preRollWindow: TimeInterval

    public init(configuration: VADConfiguration = VADConfiguration()) {
        self.configuration = configuration
        self.preRollWindow = configuration.preRollDuration
    }

    public func process(frame: AudioFrame, energy: Float, now: Date = Date()) -> VADDecision {
        updatePreRoll(frame: frame, now: now)
        switch state {
        case .idle:
            if energy > configuration.energyThreshold {
                transition(to: .attack, now: now)
                return VADDecision(state: state, shouldTransmit: false, preRollFrames: [])
            }
        case .attack:
            if now.timeIntervalSince(stateStart) >= configuration.attackDuration {
                transition(to: .talking, now: now)
                return VADDecision(state: state, shouldTransmit: true, preRollFrames: preRollBuffer)
            }
        case .talking:
            if energy <= configuration.energyThreshold {
                transition(to: .release, now: now)
            }
            return VADDecision(state: state, shouldTransmit: true, preRollFrames: [])
        case .release:
            if energy > configuration.energyThreshold {
                transition(to: .talking, now: now)
                return VADDecision(state: state, shouldTransmit: true, preRollFrames: [])
            }
            if now.timeIntervalSince(stateStart) >= configuration.releaseDuration {
                transition(to: .idle, now: now)
            }
        }
        return VADDecision(state: state, shouldTransmit: false, preRollFrames: [])
    }

    private func transition(to newState: VADState, now: Date) {
        state = newState
        stateStart = now
    }

    private func updatePreRoll(frame: AudioFrame, now: Date) {
        preRollBuffer.append(frame)
        let earliest = now.addingTimeInterval(-preRollWindow)
        preRollBuffer.removeAll { Date(timeIntervalSince1970: $0.timestamp) < earliest }
    }
}
