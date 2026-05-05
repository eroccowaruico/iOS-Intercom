import Foundation
import VADGate

enum VoiceActivitySensitivity: String, CaseIterable, Identifiable, Sendable {
    case lowNoise
    case standard
    case noisy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lowNoise:
            "Low Noise"
        case .standard:
            "Standard"
        case .noisy:
            "Noisy"
        }
    }

    var configuration: VADGateConfiguration {
        switch self {
        case .lowNoise:
            VADGateConfiguration(
                attackDuration: 0.04,
                releaseDuration: 0.45,
                speechThresholdOffsetDB: 8,
                silenceThresholdOffsetDB: 5
            )
        case .standard:
            VADGateConfiguration()
        case .noisy:
            VADGateConfiguration(
                attackDuration: 0.12,
                releaseDuration: 0.65,
                speechThresholdOffsetDB: 16,
                silenceThresholdOffsetDB: 10
            )
        }
    }
}
