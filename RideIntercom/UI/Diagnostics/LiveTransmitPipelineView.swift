import SwiftUI
import RTC
import SessionManager

struct LiveTransmitPipelineView: View {
    @Bindable var viewModel: IntercomViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 128), spacing: AppSpacing.m, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            Label("Live TX Pipeline", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                .font(AppTypography.sectionTitle)

            ViewThatFits(in: .horizontal) {
                horizontalPipeline
                gridPipeline
            }

            EffectChainStagesView(
                title: "TX Effect Chain",
                accessibilityIdentifier: "pipeline-effect-chain",
                stageIdentifierPrefix: "pipeline-effect-stage",
                stages: transmitEffectStages
            )
        }
        .appDiagnosticsCardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liveTransmitPipelineView")
    }

    private var horizontalPipeline: some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                PipelineStepView(step: step)
                    .frame(width: 124)
                    .accessibilityIdentifier(step.accessibilityIdentifier)

                if index < steps.count - 1 {
                    pipelineConnector(color: connectorColor(after: index))
                        .frame(width: AppSize.connector.width, height: AppSize.connector.height)
                        .accessibilityIdentifier("transmitPipelineConnector\(index)")
                }
            }
        }
    }

    private var gridPipeline: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.m) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                PipelineStepView(step: step)
                    .accessibilityIdentifier(step.accessibilityIdentifier)
                    .overlay(alignment: .topTrailing) {
                        Text("\(index + 1)")
                            .font(AppTypography.caption2Mono)
                            .foregroundStyle(AppColorPalette.textTertiary)
                    }
            }
        }
    }

    private var steps: [PipelineStep] {
        [
            sessionStep,
            inputStreamStep,
            mixerBusStep,
            mixerEffectChainStep,
            codecStep,
            rtcStep
        ]
    }

    private var sessionStep: PipelineStep {
        if viewModel.audioErrorMessage != nil {
            return PipelineStep(
                id: "session",
                package: "SessionManager",
                title: "Session",
                detail: "Error",
                icon: "waveform.badge.exclamationmark",
                state: .blocked,
                accessibilityIdentifier: "pipeline-session-step"
            )
        }
        if viewModel.audioSessionSnapshot.isActive {
            return PipelineStep(
                id: "session",
                package: "SessionManager",
                title: "Session",
                detail: viewModel.audioSessionProfile.label,
                icon: "waveform",
                state: .passing,
                accessibilityIdentifier: "pipeline-session-step"
            )
        }
        if viewModel.lastAudioSessionConfigurationReport != nil {
            return PipelineStep(
                id: "session",
                package: "SessionManager",
                title: "Session",
                detail: "Configured",
                icon: "waveform",
                state: .waiting,
                accessibilityIdentifier: "pipeline-session-step"
            )
        }
        return PipelineStep(
            id: "session",
            package: "SessionManager",
            title: "Session",
            detail: "Idle",
            icon: "waveform",
            state: .idle,
            accessibilityIdentifier: "pipeline-session-step"
        )
    }

    private var inputStreamStep: PipelineStep {
        if viewModel.isMuted {
            return PipelineStep(
                id: "input",
                package: "SessionManager",
                title: "Input",
                detail: inputStreamDetail("Muted"),
                icon: "mic.slash.fill",
                state: .waiting,
                accessibilityIdentifier: "pipeline-input-step"
            )
        }
        guard viewModel.isAudioReady else {
            return PipelineStep(
                id: "input",
                package: "SessionManager",
                title: "Input",
                detail: "Idle",
                icon: "mic",
                state: .idle,
                accessibilityIdentifier: "pipeline-input-step"
            )
        }
        let snapshot = viewModel.lastInputStreamOperationReport?.snapshot ?? viewModel.lastVoiceProcessingOperationReport?.snapshot
        let isRunning = snapshot?.isRunning ?? viewModel.isMicrophoneCaptureRunning
        return PipelineStep(
            id: "input",
            package: "SessionManager",
            title: "Input",
            detail: inputStreamDetail(isRunning ? "Run" : "Starting"),
            icon: isRunning ? "mic.fill" : "mic",
            state: isRunning ? .passing : .waiting,
            accessibilityIdentifier: "pipeline-input-step"
        )
    }

    private var mixerBusStep: PipelineStep {
        guard viewModel.isAudioReady else {
            return PipelineStep(
                id: "mixer",
                package: "AudioMixer",
                title: "TX Bus",
                detail: "Idle",
                icon: "slider.horizontal.3",
                state: .idle,
                accessibilityIdentifier: "pipeline-mixer-step"
            )
        }
        return PipelineStep(
            id: "mixer",
            package: "AudioMixer",
            title: "TX Bus",
            detail: "Mic -> FX",
            icon: "slider.horizontal.3",
            state: .passing,
            accessibilityIdentifier: "pipeline-mixer-step"
        )
    }

    private var mixerEffectChainStep: PipelineStep {
        guard viewModel.isAudioReady else {
            return PipelineStep(
                id: "effect-chain",
                package: "AudioMixer",
                title: "FX Chain",
                detail: "Idle",
                icon: "wand.and.sparkles",
                state: .idle,
                accessibilityIdentifier: "pipeline-effects-step"
            )
        }
        let state = effectChainState
        return PipelineStep(
            id: "effect-chain",
            package: "AudioMixer",
            title: "FX Chain",
            detail: effectChainPipelineDetail,
            icon: "wand.and.sparkles",
            state: state,
            accessibilityIdentifier: "pipeline-effects-step"
        )
    }

    private var codecStep: PipelineStep {
        guard viewModel.isAudioReady else {
            return PipelineStep(
                id: "codec",
                package: "Codec",
                title: "Codec",
                detail: "Idle",
                icon: "cpu",
                state: .idle,
                accessibilityIdentifier: "pipeline-codec-step"
            )
        }
        let isFallback = viewModel.preferredTransmitCodec != viewModel.selectedTransmitCodec
        return PipelineStep(
            id: "codec",
            package: "Codec",
            title: "Codec",
            detail: isFallback ? "\(codecPipelineDetail) / Fallback" : codecPipelineDetail,
            icon: isFallback ? "cpu" : "cpu.fill",
            state: isFallback ? .waiting : codecState,
            accessibilityIdentifier: "pipeline-codec-step"
        )
    }

    private var rtcStep: PipelineStep {
        guard viewModel.isAudioReady else {
            return PipelineStep(
                id: "rtc",
                package: "RTC",
                title: "RTC",
                detail: "Media Idle",
                icon: "dot.radiowaves.left.and.right",
                state: .idle,
                accessibilityIdentifier: "pipeline-rtc-step"
            )
        }
        guard viewModel.selectedGroupConnectionState == .localConnected || viewModel.selectedGroupConnectionState == .internetConnected else {
            return PipelineStep(
                id: "rtc",
                package: "RTC",
                title: "RTC",
                detail: "Control Waiting",
                icon: "dot.radiowaves.left.and.right",
                state: .waiting,
                accessibilityIdentifier: "pipeline-rtc-step"
            )
        }
        guard viewModel.sentVoicePacketCount > 0 else {
            return PipelineStep(
                id: "rtc",
                package: "RTC",
                title: "RTC",
                detail: "\(viewModel.routeLabel) Ready",
                icon: "dot.radiowaves.left.and.right",
                state: .waiting,
                accessibilityIdentifier: "pipeline-rtc-step"
            )
        }
        return PipelineStep(
            id: "rtc",
            package: "RTC",
            title: "RTC",
            detail: "\(viewModel.routeLabel) TX \(viewModel.sentVoicePacketCount)",
            icon: "dot.radiowaves.left.and.right",
            state: .passing,
            accessibilityIdentifier: "pipeline-rtc-step"
        )
    }

    private var effectChainState: PipelineStepState {
        aggregateState(transmitEffectStages.map(\.state))
    }

    private var codecState: PipelineStepState {
        viewModel.isVoiceActive ? .passing : .waiting
    }

    private var transmitEffectStages: [EffectChainStage] {
        [
            EffectChainStage(
                id: "sound-isolation",
                package: "SoundIsolation",
                name: "SoundIsolation",
                shortLabel: isolationEffectShortLabel,
                detail: isolationEffectDetail,
                state: isolationEffectState
            ),
            EffectChainStage(
                id: "vad-gate",
                package: "VADGate",
                name: "VADGate",
                shortLabel: vadEffectShortLabel,
                detail: vadEffectDetail,
                state: vadEffectState
            ),
            EffectChainStage(
                id: "dynamics-processor",
                package: "DynamicsProcessor",
                name: "Dynamics",
                shortLabel: "Dyn",
                detail: viewModel.isAudioReady ? "Leveling ready" : "Idle",
                state: viewModel.isAudioReady ? .passing : .idle
            ),
            EffectChainStage(
                id: "peak-limiter",
                package: "PeakLimiter",
                name: "Peak Limit",
                shortLabel: "Limit",
                detail: viewModel.isAudioReady ? "Peak guard ready" : "Idle",
                state: viewModel.isAudioReady ? .passing : .idle
            )
        ]
    }

    private var effectChainPipelineDetail: String {
        let activeStage = transmitEffectStages.first { $0.state == .blocked || $0.state == .waiting }
            ?? transmitEffectStages.last
        let focus = activeStage.map { "\($0.shortLabel) \($0.detail)" } ?? "Empty"
        return "\(transmitEffectStages.count) stages / \(focus)"
    }

    private var isolationEffectShortLabel: String {
        if !viewModel.supportsSoundIsolation {
            return "SI N/A"
        }
        return viewModel.isSoundIsolationEnabled ? "SI" : "SI Off"
    }

    private var isolationEffectDetail: String {
        if !viewModel.supportsSoundIsolation {
            return "Unavailable"
        }
        return viewModel.isSoundIsolationEnabled ? "Enabled" : "Bypassed"
    }

    private var isolationEffectState: PipelineStepState {
        guard viewModel.isAudioReady else { return .idle }
        if viewModel.isSoundIsolationEnabled && !viewModel.supportsSoundIsolation {
            return .waiting
        }
        return .passing
    }

    private var vadEffectShortLabel: String {
        if viewModel.isMuted { return "VAD Muted" }
        return viewModel.isVoiceActive ? "VAD Speech" : "VAD Silent"
    }

    private var vadEffectDetail: String {
        if viewModel.isMuted { return "Input muted" }
        return "\(viewModel.vadSensitivity.label) / \(viewModel.vadAnalysisSummary)"
    }

    private var vadEffectState: PipelineStepState {
        guard viewModel.isAudioReady else { return .idle }
        if viewModel.isMuted { return .waiting }
        return viewModel.isVoiceActive ? .passing : .waiting
    }

    private func inputStreamDetail(_ prefix: String) -> String {
        let snapshot = viewModel.lastInputStreamOperationReport?.snapshot ?? viewModel.lastVoiceProcessingOperationReport?.snapshot
        guard let snapshot else { return prefix }
        return "\(prefix) / \(streamFormatSummary(snapshot.format)) / F \(snapshot.processedFrameCount)"
    }

    private func streamFormatSummary(_ format: SessionManager.AudioStreamFormat) -> String {
        "\(Int(format.sampleRate / 1_000))k/\(format.channelCount)ch"
    }

    private var codecPipelineDetail: String {
        let requested = codecShortLabel(viewModel.preferredTransmitCodec)
        let selected = codecShortLabel(viewModel.selectedTransmitCodec)
        if requested == selected { return selected }
        return "\(requested) -> \(selected)"
    }

    private func codecShortLabel(_ codec: AudioCodecIdentifier) -> String {
        if codec == .pcm16 { return "PCM" }
        if codec == .mpeg4AACELDv2 { return "AAC" }
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

    private func aggregateState(_ states: [PipelineStepState]) -> PipelineStepState {
        if states.contains(.blocked) { return .blocked }
        if states.contains(.waiting) { return .waiting }
        if states.contains(.passing) { return .passing }
        return .idle
    }
}

struct EffectChainStage: Equatable, Identifiable {
    let id: String
    let package: String
    let name: String
    let shortLabel: String
    let detail: String
    let state: PipelineStepState
}

struct PipelineStep: Equatable, Identifiable {
    let id: String
    let package: String
    let title: String
    let detail: String
    let icon: String
    let state: PipelineStepState
    let accessibilityIdentifier: String
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

struct EffectChainStagesView: View {
    let title: String
    let accessibilityIdentifier: String
    let stageIdentifierPrefix: String
    let stages: [EffectChainStage]

    private let columns = [
        GridItem(.adaptive(minimum: 154), spacing: AppSpacing.m, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(title)
                .font(AppTypography.captionStrong)
                .foregroundStyle(AppColorPalette.textSecondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.s) {
                ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                    EffectChainStageRow(index: index + 1, stage: stage)
                        .accessibilityIdentifier("\(stageIdentifierPrefix)-\(stage.id)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct EffectChainStageRow: View {
    let index: Int
    let stage: EffectChainStage

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.m) {
            Text("\(index)")
                .font(AppTypography.caption2Mono)
                .foregroundStyle(stage.state.color)
                .frame(width: 18, alignment: .trailing)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(stage.name)
                    .font(AppTypography.captionStrong)
                    .foregroundStyle(AppColorPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("\(stage.package) / \(stage.detail)")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColorPalette.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(index) \(stage.name)")
        .accessibilityValue("\(stage.package), \(stage.detail)")
    }
}

struct PipelineStepView: View {
    let step: PipelineStep

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            Text(step.package)
                .font(AppTypography.caption2)
                .foregroundStyle(AppColorPalette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Image(systemName: step.icon)
                .font(.title3)
                .frame(width: AppSize.iconL, height: AppSize.iconL)
                .foregroundStyle(step.state.color)

            Text(step.title)
                .font(AppTypography.captionStrong)
                .foregroundStyle(AppColorPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(step.detail)
                .font(AppTypography.caption2Mono)
                .foregroundStyle(step.state.color)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .padding(AppSpacing.m)
        .background(AppColorPalette.panelSurface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.package) \(step.title)")
        .accessibilityValue(step.detail)
    }
}
