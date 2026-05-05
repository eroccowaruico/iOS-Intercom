import SwiftUI
import RTC

struct DiagnosticsView: View {
    @Bindable var viewModel: IntercomViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let snapshot = viewModel.diagnosticsSnapshot
            let now = context.date.timeIntervalSince1970

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.screen) {
                    LiveTransmitPipelineView(viewModel: viewModel)

                    VStack(alignment: .leading, spacing: AppSpacing.m) {
                        Text("Live Status")
                            .font(AppTypography.sectionTitle)
                        DiagnosticRow(
                            icon: "checklist",
                            value: "CALL \(viewModel.connectionLabel) / \(viewModel.isAudioReady ? "AUDIO READY" : "AUDIO IDLE")"
                        )
                            .accessibilityIdentifier("realDeviceCallDebugSummaryLabel")
                        DiagnosticRow(icon: "clock.arrow.circlepath", value: snapshot.reception.summary(now: now))
                            .accessibilityIdentifier("receptionDebugSummaryLabel")
                        DiagnosticRow(icon: "waveform.path.ecg", value: snapshot.audio.summary)
                            .accessibilityIdentifier("audioDebugSummaryLabel")
                        DiagnosticRow(icon: "speaker.wave.2.fill", value: snapshot.playback.summary)
                            .accessibilityIdentifier("playbackDebugSummaryLabel")
                        DiagnosticRow(icon: "person.2.fill", value: snapshot.connectionSummary)
                            .accessibilityIdentifier("connectionDebugSummaryLabel")
                        DiagnosticRow(icon: "checkmark.seal.fill", value: snapshot.authenticationSummary)
                            .accessibilityIdentifier("authenticationDebugSummaryLabel")
                        DiagnosticRow(icon: "antenna.radiowaves.left.and.right", value: snapshot.localNetwork.summary(now: now))
                            .accessibilityIdentifier("localNetworkDebugSummaryLabel")
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.m) {
                        Text("Identity & Route")
                            .font(AppTypography.sectionTitle)
                        DiagnosticRow(icon: "network", value: snapshot.transportSummary)
                            .accessibilityIdentifier("transportDebugSummaryLabel")
                        DiagnosticRow(icon: "person.text.rectangle.fill", value: snapshot.localMemberSummary)
                            .accessibilityIdentifier("localMemberDebugSummaryLabel")
                        DiagnosticRow(icon: "person.3.sequence.fill", value: snapshot.selectedGroupSummary)
                            .accessibilityIdentifier("selectedGroupDebugSummaryLabel")
                        DiagnosticRow(icon: "number", value: snapshot.groupHashSummary)
                            .accessibilityIdentifier("groupHashDebugSummaryLabel")
                        DiagnosticRow(icon: "square.and.arrow.up", value: snapshot.inviteSummary)
                            .accessibilityIdentifier("inviteDebugSummaryLabel")
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.m) {
                        Text("Input Config")
                            .font(AppTypography.sectionTitle)

                        DiagnosticRow(
                            icon: "network",
                            value: viewModel.isAudioDeviceSelectionLive ? "SESSION ACTIVE / I/O ROUTING LIVE" : "SESSION IDLE / I/O ROUTING NEXT START"
                        )
                        .accessibilityIdentifier("audioIOApplyStateLabel")

                        DiagnosticRow(icon: "waveform", value: viewModel.audioInputProcessingSummary)
                            .accessibilityLabel("Audio input processing")
                            .accessibilityValue(viewModel.audioInputProcessingSummary)
                            .accessibilityIdentifier("audioInputProcessingSummaryLabel")
                    }
                }
                .padding(AppSpacing.screen)
            }
            .accessibilityIdentifier("diagnosticsScrollView")
        }
    }
}

struct DiagnosticRow: View {
    let icon: String
    let value: String

    private var parts: [String] {
        value.components(separatedBy: " / ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.l) {
            Image(systemName: icon)
                .frame(width: AppSize.iconS)
                .foregroundStyle(AppColorPalette.textSecondary)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                ForEach(parts, id: \.self) { part in
                    Text(part)
                        .font(AppTypography.footnoteMono)
                        .foregroundStyle(AppColorPalette.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appDiagnosticsCardStyle()
    }
}
