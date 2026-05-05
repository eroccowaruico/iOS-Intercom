import SwiftUI
import RTC

struct SettingsView: View {
    @Bindable var viewModel: IntercomViewModel

    var body: some View {
        Form {
            AudioIOPanel(viewModel: viewModel)
            AudioCheckPanel(viewModel: viewModel)
            TransmitCodecPanel(viewModel: viewModel)
            VADThresholdPanel(viewModel: viewModel)
            ResetSettingsPanel(viewModel: viewModel)
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settingsScrollView")
    }
}

struct AudioIOPanel: View {
    @Bindable var viewModel: IntercomViewModel

    var body: some View {
        Section {
            if viewModel.availableOutputPorts.count > 1 {
                AudioPortPicker(
                    title: "Output",
                    selection: Binding(
                        get: { viewModel.selectedOutputPort },
                        set: { viewModel.setOutputPort($0) }
                    ),
                    ports: viewModel.availableOutputPorts,
                    accessibilityIdentifier: "audioCheckOutputPicker"
                )
            }

            if viewModel.availableInputPorts.count > 1 {
                AudioPortPicker(
                    title: "Input",
                    selection: Binding(
                        get: { viewModel.selectedInputPort },
                        set: { viewModel.setInputPort($0) }
                    ),
                    ports: viewModel.availableInputPorts,
                    accessibilityIdentifier: "audioCheckInputPicker"
                )
            }

            if viewModel.supportsSoundIsolation {
                Toggle(
                    "Sound Isolation",
                    isOn: Binding(
                        get: { viewModel.isSoundIsolationEnabled },
                        set: { viewModel.setSoundIsolationEnabled($0) }
                    )
                )
                .accessibilityIdentifier("soundIsolationToggle")
            }

            if viewModel.supportsAdvancedMixingOptions {
                Toggle(
                    "Duck Other Audio",
                    isOn: Binding(
                        get: { viewModel.isDuckOthersEnabled },
                        set: { viewModel.setDuckOthersEnabled($0) }
                    )
                )
                .accessibilityIdentifier("duckOthersToggle")
            }
        } header: {
            Label("Audio I/O", systemImage: "waveform")
        }
        .accessibilityIdentifier("audioIOPanel")
    }
}

struct TransmitCodecPanel: View {
    @Bindable var viewModel: IntercomViewModel

    var body: some View {
        Section {
            Picker("Codec", selection: Binding(
                get: { viewModel.preferredTransmitCodec },
                set: { viewModel.setPreferredTransmitCodec($0) }
            )) {
                Text("PCM 16-bit").tag(AudioCodecIdentifier.pcm16)
                Text("HE-AAC v2 VBR").tag(AudioCodecIdentifier.heAACv2)
                Text("Opus").tag(AudioCodecIdentifier.opus)
            }
            .pickerStyle(.segmented)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("transmitCodecPicker")
        } header: {
            Label("Transmit Codec", systemImage: "antenna.radiowaves.left.and.right")
        }
        .accessibilityIdentifier("transmitCodecPanel")
    }
}

struct AudioCheckPanel: View {
    @Bindable var viewModel: IntercomViewModel

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text("Call")
                Spacer()
                VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                    Text(viewModel.isAudioReady ? "Call Live" : "Call Idle")
                        .font(AppTypography.bodyStrong)
                        .foregroundStyle(viewModel.isAudioReady ? AppColorPalette.success : AppColorPalette.textSecondary)
                        .accessibilityIdentifier("liveAudioStateLabel")
                    Text(viewModel.audioCheckPhase.rawValue)
                        .font(AppTypography.captionStrongMono)
                        .foregroundStyle(statusColor)
                        .accessibilityIdentifier("audioCheckPhaseLabel")
                }
            }

            AudioCheckMeterSection(
                title: "Microphone Input",
                systemImage: "mic.fill",
                level: viewModel.diagnosticsInputLevel,
                peakLevel: viewModel.diagnosticsInputPeakLevel,
                isMuted: viewModel.isMuted,
                accessibilityIdentifier: "audioCheckInputMeter"
            )
            .listRowSeparator(.hidden)

            AudioCheckMeterSection(
                title: "Speaker Output",
                systemImage: "speaker.wave.2.fill",
                level: viewModel.diagnosticsOutputLevel,
                peakLevel: viewModel.diagnosticsOutputPeakLevel,
                isMuted: false,
                accessibilityIdentifier: "audioCheckOutputMeter"
            )
            .listRowSeparator(.hidden)

            Text(viewModel.audioCheckStatusMessage)
                .font(AppTypography.footnote)
                .foregroundStyle(AppColorPalette.textSecondary)
                .lineLimit(nil)
                .accessibilityIdentifier("audioCheckStatusLabel")

            Button {
                viewModel.startAudioCheck()
            } label: {
                Label("Record 5s and Play", systemImage: "record.circle.fill")
            }
            .appProminentButtonStyle()
            .controlSize(.large)
            .disabled(viewModel.audioCheckPhase == .recording || viewModel.audioCheckPhase == .playing)
            .accessibilityValue(viewModel.audioCheckPhase.rawValue)
            .accessibilityIdentifier("audioCheckButton")
        } header: {
            Label("Audio Check", systemImage: "waveform")
        }
        .accessibilityIdentifier("audioCheckPanel")
    }

    private var statusColor: Color {
        switch viewModel.audioCheckPhase {
        case .idle:
            AppColorPalette.neutral
        case .recording:
            AppColorPalette.danger
        case .playing:
            AppColorPalette.success
        case .completed:
            AppColorPalette.info
        case .failed:
            AppColorPalette.danger
        }
    }

}

struct VADThresholdPanel: View {
    @Bindable var viewModel: IntercomViewModel

    var body: some View {
        Section {
            HStack {
                Text("Voice Activity Detection Threshold")
                Spacer()
                Text(String(format: "%.4f", viewModel.voiceActivityDetectionThreshold))
                    .font(AppTypography.captionStrongMono)
                    .foregroundStyle(AppColorPalette.textSecondary)
            }

            Slider(
                value: Binding(
                    get: { Double(viewModel.voiceActivityDetectionThreshold) },
                    set: {
                        let minValue = Double(VoiceActivityDetector.minThreshold)
                        let maxValue = Double(VoiceActivityDetector.maxThreshold)
                        let clamped = min(max(minValue, $0), maxValue)
                        let step = 0.00025
                        let snapped = (clamped / step).rounded() * step
                        viewModel.setVoiceActivityDetectionThreshold(Float(min(max(minValue, snapped), maxValue)))
                    }
                ),
                in: Double(VoiceActivityDetector.minThreshold)...Double(VoiceActivityDetector.maxThreshold)
            )
            .accessibilityIdentifier("voiceActivityDetectionThresholdSlider")
        } header: {
            Label("VAD Threshold", systemImage: "waveform.badge.mic")
        }
        .accessibilityIdentifier("vadThresholdPanel")
    }
}

struct ResetSettingsPanel: View {
    @Bindable var viewModel: IntercomViewModel

    var body: some View {
        Section {
            Button(role: .destructive) {
                viewModel.resetAllSettings()
            } label: {
                Label("Reset All Settings", systemImage: "arrow.counterclockwise")
            }
            .accessibilityIdentifier("resetAllSettingsButton")
        } footer: {
            Text("Resets audio and call settings to their default values. Saved groups and members are not changed.")
        }
        .accessibilityIdentifier("resetSettingsPanel")
    }
}
