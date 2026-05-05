import SwiftUI
import RTC

struct LiveTransmitPipelineView: View {
    @Bindable var viewModel: IntercomViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            Label("Live TX Pipeline", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(AppTypography.sectionTitle)

            HStack(alignment: .top, spacing: AppSpacing.xs) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    PipelineStepView(step: step)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("transmitPipelineStep\(index)")

                    if index < steps.count - 1 {
                        pipelineConnector(color: connectorColor(after: index))
                            .frame(width: AppSize.connector.width, height: AppSize.connector.height)
                            .accessibilityIdentifier("transmitPipelineConnector\(index)")
                    }
                }
            }
        }
        .appDiagnosticsCardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liveTransmitPipelineView")
    }

    private var steps: [PipelineStep] {
        [
            micStep,
            muteIsolationStep,
            vadStep,
            encodeStep,
            sendStep
        ]
    }

    private var micStep: PipelineStep {
        if viewModel.audioErrorMessage != nil {
            return PipelineStep(title: "Mic", detail: "Error", icon: "mic.slash.fill", state: .blocked)
        }
        if viewModel.isAudioReady, !viewModel.isMicrophoneCaptureRunning {
            return PipelineStep(title: "Mic", detail: "Off", icon: "mic.slash.fill", state: .blocked)
        }
        if viewModel.isAudioReady {
            let detail = viewModel.diagnosticsInputLevel > 0 ? "Input" : "Ready"
            return PipelineStep(title: "Mic", detail: detail, icon: "mic.fill", state: .passing)
        }
        return PipelineStep(title: "Mic", detail: "Idle", icon: "mic", state: .idle)
    }

    private var muteIsolationStep: PipelineStep {
        if viewModel.isMuted {
            let detail = viewModel.isMicrophoneCaptureRunning ? "Muted" : "Muted + Mic Off"
            return PipelineStep(title: "Mute", detail: detail, icon: "mic.slash.fill", state: .blocked)
        }
        let detail = viewModel.isSoundIsolationEnabled ? "Iso On" : "Open"
        return PipelineStep(title: "Input FX", detail: detail, icon: "waveform", state: viewModel.isAudioReady ? .passing : .idle)
    }

    private var vadStep: PipelineStep {
        if viewModel.isMuted {
            return PipelineStep(title: "VAD", detail: "Muted", icon: "waveform.slash", state: .idle)
        }
        if viewModel.isVoiceActive {
            return PipelineStep(title: "VAD", detail: "Voice", icon: "waveform.badge.mic", state: .passing)
        }
        return PipelineStep(title: "VAD", detail: viewModel.isAudioReady ? "Silent" : "Waiting", icon: "waveform.slash", state: viewModel.isAudioReady ? .waiting : .idle)
    }

    private var encodeStep: PipelineStep {
        guard viewModel.isAudioReady else {
            return PipelineStep(title: "Encode", detail: "Idle", icon: "cpu", state: .idle)
        }
        guard viewModel.isVoiceActive else {
            return PipelineStep(title: "Encode", detail: codecLabel, icon: "cpu", state: .waiting)
        }
        return PipelineStep(title: "Encode", detail: codecLabel, icon: "cpu.fill", state: .passing)
    }

    private var sendStep: PipelineStep {
        guard viewModel.isAudioReady else {
            return PipelineStep(title: "Send", detail: "Idle", icon: "paperplane", state: .idle)
        }
        guard viewModel.selectedGroupConnectionState == .localConnected || viewModel.selectedGroupConnectionState == .internetConnected else {
            return PipelineStep(title: "Send", detail: "Waiting", icon: "paperplane", state: .waiting)
        }
        guard viewModel.sentVoicePacketCount > 0 else {
            return PipelineStep(title: "Send", detail: "Ready", icon: "paperplane", state: .waiting)
        }
        return PipelineStep(title: "Send", detail: "TX \(viewModel.sentVoicePacketCount)", icon: "paperplane.fill", state: .passing)
    }

    private var codecLabel: String {
        let codec = viewModel.preferredTransmitCodec
        if codec == .pcm16 { return "PCM" }
        if codec == .heAACv2 { return "AAC" }
        if codec == .opus { return "Opus" }
        return codec.rawValue
    }

    private func connectorColor(after index: Int) -> Color {
        let left = steps[index].state
        let right = steps[index + 1].state
        if left == .blocked || right == .blocked {
            return AppColorPalette.danger
        }
        if left == .passing && right == .passing {
            return AppColorPalette.success
        }
        if left == .passing || right == .waiting {
            return AppColorPalette.warning
        }
        return AppColorPalette.connectorNeutral
    }

    private func pipelineConnector(color: Color) -> some View {
        Text(">")
            .font(.system(size: 11, weight: .regular, design: .default))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct PipelineStep: Equatable {
    let title: String
    let detail: String
    let icon: String
    let state: PipelineStepState
}

enum PipelineStepState: Equatable {
    case passing
    case waiting
    case blocked
    case idle

    var color: Color {
        switch self {
        case .passing:
            AppColorPalette.success
        case .waiting:
            AppColorPalette.warning
        case .blocked:
            AppColorPalette.danger
        case .idle:
            AppColorPalette.neutral
        }
    }
}

struct PipelineStepView: View {
    let step: PipelineStep

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            Image(systemName: step.icon)
                .font(.title3)
                .frame(width: AppSize.iconL, height: AppSize.iconL)
                .foregroundStyle(step.state.color)
            Text(step.title)
                .font(AppTypography.captionStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(step.detail)
                .font(AppTypography.caption2)
                .foregroundStyle(step.state.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minWidth: AppSize.iconL)
        .accessibilityElement(children: .contain)
    }
}
