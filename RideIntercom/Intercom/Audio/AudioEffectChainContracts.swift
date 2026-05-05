import Foundation

enum AudioEffectStageRuntimeState: Equatable, Sendable {
    case active
    case bypassed
    case unavailable
    case waiting
    case idle
}

struct AudioEffectStageSnapshot: Equatable, Identifiable, Sendable {
    let id: String
    let package: String
    let name: String
    let shortLabel: String
    let detail: String
    let state: AudioEffectStageRuntimeState
}

struct AudioEffectChainSnapshot: Equatable, Identifiable, Sendable {
    let id: String
    let stages: [AudioEffectStageSnapshot]

    var summary: String {
        guard let focus = stages.first(where: { $0.state == .unavailable || $0.state == .waiting }) ?? stages.last else {
            return "No effects"
        }
        return "\(stages.count) stages / \(focus.shortLabel) \(focus.detail)"
    }

    var compactSummary: String {
        guard !stages.isEmpty else { return "none" }
        return stages.map(\.shortLabel).joined(separator: ", ")
    }
}
