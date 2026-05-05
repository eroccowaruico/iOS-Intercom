import SwiftUI
import RTC
import SessionManager

struct LiveReceivePipelineView: View {
    @Bindable var viewModel: IntercomViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 128), spacing: AppSpacing.m, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            Label("Live RX Pipeline", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                .font(AppTypography.sectionTitle)

            ViewThatFits(in: .horizontal) {
                horizontalPipeline
                gridPipeline
            }

            ReceiveMixTopologyView(
                peerBuses: receivePeerBuses,
                master: receiveMasterMix
            )
            .accessibilityIdentifier("receive-mix-topology")

            EffectChainStagesView(
                title: "RX Peer Effect Chain",
                accessibilityIdentifier: "receive-peer-effect-chain",
                stageIdentifierPrefix: "receive-peer-effect-stage",
                stages: peerEffectStages
            )

            EffectChainStagesView(
                title: "RX Master Effect Chain",
                accessibilityIdentifier: "receive-master-effect-chain",
                stageIdentifierPrefix: "receive-master-effect-stage",
                stages: masterEffectStages
            )
        }
        .appDiagnosticsCardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liveReceivePipelineView")
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
                        .accessibilityIdentifier("receivePipelineConnector\(index)")
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
            rtcReceiveStep,
            codecDecodeStep,
            peerBusStep,
            peerEffectChainStep,
            receiveMixStep,
            masterBusStep,
            masterEffectChainStep,
            outputStep
        ]
    }

    private var rtcReceiveStep: PipelineStep {
        guard viewModel.isAudioReady else {
            return PipelineStep(
                id: "rtc-receive",
                package: "RTC",
                title: "RTC RX",
                detail: "Media Idle",
                icon: "dot.radiowaves.left.and.right",
                state: .idle,
                accessibilityIdentifier: "receive-pipeline-rtc-step"
            )
        }
        guard viewModel.selectedGroupConnectionState == .localConnected || viewModel.selectedGroupConnectionState == .internetConnected else {
            return PipelineStep(
                id: "rtc-receive",
                package: "RTC",
                title: "RTC RX",
                detail: "Control Waiting",
                icon: "dot.radiowaves.left.and.right",
                state: .waiting,
                accessibilityIdentifier: "receive-pipeline-rtc-step"
            )
        }
        if viewModel.receivedVoicePacketCount > 0 {
            return PipelineStep(
                id: "rtc-receive",
                package: "RTC",
                title: "RTC RX",
                detail: "\(viewModel.routeLabel) RX \(viewModel.receivedVoicePacketCount)",
                icon: "dot.radiowaves.left.and.right",
                state: .passing,
                accessibilityIdentifier: "receive-pipeline-rtc-step"
            )
        }
        return PipelineStep(
            id: "rtc-receive",
            package: "RTC",
            title: "RTC RX",
            detail: "\(viewModel.routeLabel) Ready",
            icon: "dot.radiowaves.left.and.right",
            state: .waiting,
            accessibilityIdentifier: "receive-pipeline-rtc-step"
        )
    }

    private var codecDecodeStep: PipelineStep {
        guard viewModel.isAudioReady else {
            return PipelineStep(
                id: "codec-decode",
                package: "Codec",
                title: "Decode",
                detail: "Idle",
                icon: "cpu",
                state: .idle,
                accessibilityIdentifier: "receive-pipeline-codec-step"
            )
        }
        if viewModel.droppedAudioPacketCount > 0 {
            return PipelineStep(
                id: "codec-decode",
                package: "Codec",
                title: "Decode",
                detail: "\(codecLabel) / DROP \(viewModel.droppedAudioPacketCount)",
                icon: "cpu",
                state: .waiting,
                accessibilityIdentifier: "receive-pipeline-codec-step"
            )
        }
        return PipelineStep(
            id: "codec-decode",
            package: "Codec",
            title: "Decode",
            detail: viewModel.receivedVoicePacketCount > 0 ? codecLabel : "\(codecLabel) Ready",
            icon: viewModel.receivedVoicePacketCount > 0 ? "cpu.fill" : "cpu",
            state: viewModel.receivedVoicePacketCount > 0 ? .passing : .waiting,
            accessibilityIdentifier: "receive-pipeline-codec-step"
        )
    }

    private var peerBusStep: PipelineStep {
        guard viewModel.isAudioReady else {
            return PipelineStep(
                id: "peer-bus",
                package: "AudioMixer",
                title: "Peer Buses",
                detail: "Idle",
                icon: "person.2.wave.2",
                state: .idle,
                accessibilityIdentifier: "receive-pipeline-peer-bus-step"
            )
        }
        return PipelineStep(
            id: "peer-bus",
            package: "AudioMixer",
            title: "Peer Buses",
            detail: "\(receivePeerBusCount) buses / RX \(viewModel.receivedVoicePacketCount)",
            icon: "person.2.wave.2",
            state: viewModel.receivedVoicePacketCount > 0 ? .passing : .waiting,
            accessibilityIdentifier: "receive-pipeline-peer-bus-step"
        )
    }

    private var peerEffectChainStep: PipelineStep {
        guard viewModel.isAudioReady else {
            return PipelineStep(
                id: "peer-effects",
                package: "AudioMixer",
                title: "Peer FX",
                detail: "Idle",
                icon: "wand.and.sparkles",
                state: .idle,
                accessibilityIdentifier: "receive-pipeline-peer-effects-step"
            )
        }
        return PipelineStep(
            id: "peer-effects",
            package: "AudioMixer",
            title: "Peer FX",
            detail: effectChainDetail(peerEffectStages),
            icon: "wand.and.sparkles",
            state: aggregateState(peerEffectStages.map(\.state)),
            accessibilityIdentifier: "receive-pipeline-peer-effects-step"
        )
    }

    private var receiveMixStep: PipelineStep {
        guard viewModel.isAudioReady else {
            return PipelineStep(
                id: "receive-mix",
                package: "AudioMixer",
                title: "Mix Down",
                detail: "Idle",
                icon: "arrow.triangle.merge",
                state: .idle,
                accessibilityIdentifier: "receive-pipeline-mix-step"
            )
        }
        let sourceCount = receivePeerBusCount
        return PipelineStep(
            id: "receive-mix",
            package: "AudioMixer",
            title: "Mix Down",
            detail: "\(sourceCount) buses -> master",
            icon: "arrow.triangle.merge",
            state: viewModel.receivedVoicePacketCount > 0 ? .passing : .waiting,
            accessibilityIdentifier: "receive-pipeline-mix-step"
        )
    }

    private var masterBusStep: PipelineStep {
        guard viewModel.isAudioReady else {
            return PipelineStep(
                id: "master-bus",
                package: "AudioMixer",
                title: "RX Master",
                detail: "Idle",
                icon: "waveform.path.ecg",
                state: .idle,
                accessibilityIdentifier: "receive-pipeline-master-bus-step"
            )
        }
        return PipelineStep(
            id: "master-bus",
            package: "AudioMixer",
            title: "RX Master",
            detail: "\(receivePeerBusCount) in / OUT \(Int(viewModel.masterOutputVolume * 100))%",
            icon: "waveform.path.ecg",
            state: viewModel.playedAudioFrameCount > 0 ? .passing : .waiting,
            accessibilityIdentifier: "receive-pipeline-master-bus-step"
        )
    }

    private var masterEffectChainStep: PipelineStep {
        guard viewModel.isAudioReady else {
            return PipelineStep(
                id: "master-effects",
                package: "AudioMixer",
                title: "Master FX",
                detail: "Idle",
                icon: "wand.and.sparkles",
                state: .idle,
                accessibilityIdentifier: "receive-pipeline-master-effects-step"
            )
        }
        return PipelineStep(
            id: "master-effects",
            package: "AudioMixer",
            title: "Master FX",
            detail: effectChainDetail(masterEffectStages),
            icon: "wand.and.sparkles",
            state: aggregateState(masterEffectStages.map(\.state)),
            accessibilityIdentifier: "receive-pipeline-master-effects-step"
        )
    }

    private var outputStep: PipelineStep {
        if viewModel.isOutputMuted || viewModel.masterOutputVolume == 0 {
            return PipelineStep(
                id: "output",
                package: "SessionManager",
                title: "Output",
                detail: viewModel.isOutputMuted ? "Muted" : "Volume 0%",
                icon: "speaker.slash.fill",
                state: .waiting,
                accessibilityIdentifier: "receive-pipeline-output-step"
            )
        }
        guard viewModel.isAudioReady else {
            return PipelineStep(
                id: "output",
                package: "SessionManager",
                title: "Output",
                detail: "Idle",
                icon: "speaker",
                state: .idle,
                accessibilityIdentifier: "receive-pipeline-output-step"
            )
        }
        let snapshot = viewModel.lastOutputStreamOperationReport?.snapshot
        let detail = outputStreamDetail(snapshot: snapshot)
        return PipelineStep(
            id: "output",
            package: "SessionManager",
            title: "Output",
            detail: detail,
            icon: "speaker.wave.2.fill",
            state: viewModel.playedAudioFrameCount > 0 ? .passing : .waiting,
            accessibilityIdentifier: "receive-pipeline-output-step"
        )
    }

    private var peerEffectStages: [EffectChainStage] {
        [
            EffectChainStage(
                id: "sound-isolation",
                package: "SoundIsolation",
                name: "SoundIsolation",
                shortLabel: receiveIsolationShortLabel,
                detail: receiveIsolationDetail,
                state: receiveIsolationState
            )
        ]
    }

    private var masterEffectStages: [EffectChainStage] {
        [
            EffectChainStage(
                id: "sound-isolation",
                package: "SoundIsolation",
                name: "SoundIsolation",
                shortLabel: receiveIsolationShortLabel,
                detail: receiveIsolationDetail,
                state: receiveIsolationState
            )
        ]
    }

    private var receivePeerBuses: [ReceivePeerBusSnapshot] {
        var snapshots: [ReceivePeerBusSnapshot] = []
        if let selectedGroup = viewModel.selectedGroup {
            snapshots = selectedGroup.members.dropFirst().compactMap { member in
                let shouldShowBus = viewModel.authenticatedPeerIDs.contains(member.id)
                    || member.connectionState != .offline
                    || member.receivedAudioPacketCount > 0
                    || member.playedAudioFrameCount > 0
                guard shouldShowBus else { return nil }
                return ReceivePeerBusSnapshot(
                    id: member.id,
                    displayName: member.displayName,
                    receivedFrameCount: member.receivedAudioPacketCount,
                    queuedFrameCount: member.queuedAudioFrameCount,
                    playedFrameCount: member.playedAudioFrameCount,
                    level: member.voiceLevel,
                    peakLevel: member.voicePeakLevel,
                    isMuted: member.isMuted,
                    state: state(for: member.audioPipelineState)
                )
            }
        }

        let existingPeerIDs = Set(snapshots.map(\.id))
        for peerID in viewModel.authenticatedPeerIDs where !existingPeerIDs.contains(peerID) {
            snapshots.append(
                ReceivePeerBusSnapshot(
                    id: peerID,
                    displayName: peerID,
                    receivedFrameCount: 0,
                    queuedFrameCount: 0,
                    playedFrameCount: 0,
                    level: 0,
                    peakLevel: 0,
                    isMuted: false,
                    state: viewModel.receivedVoicePacketCount > 0 ? .passing : .waiting
                )
            )
        }
        return snapshots
    }

    private var receivePeerBusCount: Int {
        max(receivePeerBuses.count, viewModel.authenticatedPeerCount)
    }

    private var receiveMasterMix: ReceiveMasterMixSnapshot {
        ReceiveMasterMixSnapshot(
            sourceBusCount: receivePeerBusCount,
            receivedFrameCount: viewModel.receivedVoicePacketCount,
            playedFrameCount: viewModel.playedAudioFrameCount,
            outputLevel: viewModel.diagnosticsOutputLevel,
            outputPeakLevel: viewModel.diagnosticsOutputPeakLevel,
            masterVolume: viewModel.masterOutputVolume,
            isMuted: viewModel.isOutputMuted,
            state: viewModel.playedAudioFrameCount > 0 ? .passing : (viewModel.isAudioReady ? .waiting : .idle)
        )
    }

    private var receiveIsolationShortLabel: String {
        if !viewModel.supportsSoundIsolation { return "SI N/A" }
        return viewModel.isSoundIsolationEnabled ? "SI" : "SI Off"
    }

    private var receiveIsolationDetail: String {
        if !viewModel.supportsSoundIsolation { return "Unavailable" }
        return viewModel.isSoundIsolationEnabled ? "Enabled" : "Bypassed"
    }

    private var receiveIsolationState: PipelineStepState {
        guard viewModel.isAudioReady else { return .idle }
        if viewModel.isSoundIsolationEnabled && !viewModel.supportsSoundIsolation {
            return .waiting
        }
        return .passing
    }

    private func effectChainDetail(_ stages: [EffectChainStage]) -> String {
        let activeStage = stages.first { $0.state == .blocked || $0.state == .waiting } ?? stages.last
        let focus = activeStage.map { "\($0.shortLabel) \($0.detail)" } ?? "Empty"
        return "\(stages.count) stages / \(focus)"
    }

    private func outputStreamDetail(snapshot: SessionManager.AudioStreamSnapshot?) -> String {
        guard let snapshot else {
            return viewModel.playedAudioFrameCount > 0 ? "Scheduled" : "Ready"
        }
        return "\(snapshot.isRunning ? "Run" : "Idle") / \(streamFormatSummary(snapshot.format)) / F \(snapshot.processedFrameCount)"
    }

    private func streamFormatSummary(_ format: SessionManager.AudioStreamFormat) -> String {
        "\(Int(format.sampleRate / 1_000))k/\(format.channelCount)ch"
    }

    private var codecLabel: String {
        let codec = viewModel.selectedTransmitCodec
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

    private func state(for audioPipelineState: AudioPipelineState) -> PipelineStepState {
        switch audioPipelineState {
        case .receiving, .playing:
            return .passing
        case .received:
            return .waiting
        case .idle:
            return .idle
        }
    }
}

private struct ReceivePeerBusSnapshot: Identifiable, Equatable {
    let id: String
    let displayName: String
    let receivedFrameCount: Int
    let queuedFrameCount: Int
    let playedFrameCount: Int
    let level: Float
    let peakLevel: Float
    let isMuted: Bool
    let state: PipelineStepState
}

private struct ReceiveMasterMixSnapshot: Equatable {
    let sourceBusCount: Int
    let receivedFrameCount: Int
    let playedFrameCount: Int
    let outputLevel: Float
    let outputPeakLevel: Float
    let masterVolume: Float
    let isMuted: Bool
    let state: PipelineStepState
}

private struct ReceiveMixTopologyView: View {
    let peerBuses: [ReceivePeerBusSnapshot]
    let master: ReceiveMasterMixSnapshot

    private let columns = [
        GridItem(.adaptive(minimum: 172), spacing: AppSpacing.m, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.m) {
                Text("Receive Mix Topology")
                    .font(AppTypography.captionStrong)
                    .foregroundStyle(AppColorPalette.textSecondary)

                Text("\(master.sourceBusCount) peer buses -> receive master")
                    .font(AppTypography.caption2Mono)
                    .foregroundStyle(master.state.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.m) {
                if peerBuses.isEmpty {
                    EmptyReceivePeerBusesCard()
                        .accessibilityIdentifier("receive-peer-buses-empty")
                } else {
                    ForEach(Array(peerBuses.enumerated()), id: \.element.id) { index, peerBus in
                        ReceivePeerBusCard(index: index + 1, peerBus: peerBus)
                            .accessibilityIdentifier("receive-peer-bus-\(index)")
                    }
                }

                ReceiveMasterMixCard(master: master)
                    .accessibilityIdentifier("receive-master-mix-card")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct EmptyReceivePeerBusesCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Label("Peer Buses", systemImage: "person.2.slash")
                .font(AppTypography.captionStrong)
                .foregroundStyle(AppColorPalette.neutral)
            Text("No authenticated peer bus")
                .font(AppTypography.caption2Mono)
                .foregroundStyle(AppColorPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(AppSpacing.m)
        .background(AppColorPalette.panelSurface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No authenticated peer bus")
    }
}

private struct ReceivePeerBusCard: View {
    let index: Int
    let peerBus: ReceivePeerBusSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.s) {
                Text("Bus \(index)")
                    .font(AppTypography.caption2Mono)
                    .foregroundStyle(peerBus.state.color)

                Text(peerBus.displayName)
                    .font(AppTypography.captionStrong)
                    .foregroundStyle(AppColorPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Text("RX \(peerBus.receivedFrameCount) / JIT \(peerBus.queuedFrameCount) / PLAY \(peerBus.playedFrameCount)")
                .font(AppTypography.caption2Mono)
                .foregroundStyle(AppColorPalette.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            VoiceMeterView(
                level: peerBus.isMuted ? 0 : peerBus.level,
                peakLevel: peerBus.isMuted ? 0 : peerBus.peakLevel,
                isMuted: peerBus.isMuted,
                showsValueText: false
            )
        }
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
        .padding(AppSpacing.m)
        .background(AppColorPalette.panelSurface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Receive peer bus \(index) \(peerBus.displayName)")
        .accessibilityValue("Received \(peerBus.receivedFrameCount), played \(peerBus.playedFrameCount)")
    }
}

private struct ReceiveMasterMixCard: View {
    let master: ReceiveMasterMixSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Label("Mix Down -> RX Master", systemImage: "arrow.triangle.merge")
                .font(AppTypography.captionStrong)
                .foregroundStyle(master.state.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text("\(master.sourceBusCount) buses / RX \(master.receivedFrameCount) / PLAY \(master.playedFrameCount)")
                .font(AppTypography.caption2Mono)
                .foregroundStyle(AppColorPalette.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Text(master.isMuted ? "OUT muted" : "OUT \(Int(master.masterVolume * 100))%")
                .font(AppTypography.caption2Mono)
                .foregroundStyle(master.isMuted ? AppColorPalette.warning : master.state.color)

            VoiceMeterView(
                level: master.isMuted ? 0 : master.outputLevel,
                peakLevel: master.isMuted ? 0 : master.outputPeakLevel,
                isMuted: master.isMuted,
                showsValueText: false
            )
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(AppSpacing.m)
        .background(AppColorPalette.panelSurface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Receive mix down to master")
        .accessibilityValue("\(master.sourceBusCount) peer buses, played \(master.playedFrameCount)")
    }
}
