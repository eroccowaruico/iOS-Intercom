import Testing
@testable import SessionManager

@Test func defaultConfigurationResolvesLatestIOSOptions() throws {
    let resolved = try AudioSessionConfiguration().resolved()

    #expect(resolved.category == .playAndRecord)
    #expect(resolved.mode == .default)
    #expect(resolved.options == [
        .allowBluetoothA2DP,
        .allowBluetoothHFP,
        .bluetoothHighQualityRecording,
        .duckOthers,
        .farFieldInput,
        .mixWithOthers,
        .overrideMutedMicrophoneInterruption,
    ])
    #expect(resolved.prefersEchoCancelledInput == false)
}

@Test func defaultToSpeakerIsOptIn() throws {
    let defaultResolved = try AudioSessionConfiguration().resolved()
    let speakerResolved = try AudioSessionConfiguration(defaultToSpeaker: true).resolved()

    #expect(!defaultResolved.options.contains(.defaultToSpeaker))
    #expect(speakerResolved.options.contains(.defaultToSpeaker))
}

@Test func voiceChatDoesNotApplyEchoCancelledInputPreference() throws {
    let resolved = try AudioSessionConfiguration(mode: .voiceChat).resolved()

    #expect(resolved.mode == .voiceChat)
    #expect(resolved.prefersEchoCancelledInput == nil)
}

@Test func echoCancelledInputRequiresDefaultMode() {
    do {
        _ = try AudioSessionConfiguration(mode: .voiceChat, prefersEchoCancelledInput: true).resolved()
        Issue.record("voiceChat must reject explicit echo-cancelled input preference")
    } catch {
        #expect(error as? AudioSessionManagerError == .echoCancelledInputRequiresDefaultMode)
    }
}

@Test func managerAppliesConfigurationBeforeActivating() throws {
    let backend = FakeAudioSessionBackend()
    let manager = AudioSessionManager(backend: backend)
    let input = AudioSessionDevice(id: "mic-1", name: "Helmet Mic", direction: .input)
    let output = AudioSessionDevice(id: "speaker-1", name: "Helmet Speaker", direction: .output)

    try manager.configure(
        AudioSessionConfiguration(
            defaultToSpeaker: true,
            prefersEchoCancelledInput: true,
            preferredInput: .device(input.id),
            preferredOutput: .device(output.id)
        )
    )
    try manager.setActive(true)

    #expect(backend.events == [
        .applyConfiguration,
        .setPreferredInput(input.id),
        .setPreferredOutput(output.id),
        .setPrefersEchoCancelledInput(true),
        .setActive(true),
    ])
    #expect(backend.appliedConfigurations.first?.options.contains(.defaultToSpeaker) == true)
}

@Test func managerCanReturnToSystemDefaultDevices() throws {
    let backend = FakeAudioSessionBackend()
    let manager = AudioSessionManager(backend: backend)

    try manager.configure(
        AudioSessionConfiguration(
            preferredInput: .systemDefault,
            preferredOutput: .systemDefault
        )
    )

    #expect(backend.events == [
        .applyConfiguration,
        .setPreferredInput(nil),
        .setPreferredOutput(nil),
        .setPrefersEchoCancelledInput(false),
    ])
}

@Test func managerExposesSnapshotFromBackend() throws {
    let backend = FakeAudioSessionBackend()
    let input = AudioSessionDevice(id: "mic-1", name: "Helmet Mic", direction: .input)
    let output = AudioSessionDevice(id: "speaker-1", name: "Helmet Speaker", direction: .output)
    backend.snapshot = AudioSessionSnapshot(
        isActive: true,
        availableInputs: [.systemDefaultInput, input],
        availableOutputs: [.systemDefaultOutput, output],
        currentInput: input,
        currentOutput: output
    )
    let manager = AudioSessionManager(backend: backend)

    let snapshot = try manager.snapshot()

    #expect(snapshot.isActive)
    #expect(snapshot.availableInputs == [.systemDefaultInput, input])
    #expect(snapshot.availableOutputs == [.systemDefaultOutput, output])
    #expect(snapshot.currentInput == input)
    #expect(snapshot.currentOutput == output)
}

@Test func voiceProcessingEnablesAdvancedDuckingWithoutStoppingInput() throws {
    let backend = FakeVoiceProcessingBackend()
    let manager = AudioInputVoiceProcessingManager(backend: backend)

    try manager.configure(
        AudioInputVoiceProcessingConfiguration(
            soundIsolationEnabled: false,
            otherAudioDuckingEnabled: true,
            duckingLevel: .normal,
            inputMuted: true
        )
    )

    #expect(backend.events == [
        .setVoiceProcessingEnabled(true),
        .setAdvancedDucking(enabled: true, level: .normal),
        .setVoiceProcessingBypassed(true),
        .setInputMuted(true),
    ])
}

@Test func voiceProcessingKeepsMinimumDuckingWhenDuckingIsDisabled() throws {
    let backend = FakeVoiceProcessingBackend()
    let manager = AudioInputVoiceProcessingManager(backend: backend)

    try manager.configure(
        AudioInputVoiceProcessingConfiguration(
            soundIsolationEnabled: true,
            otherAudioDuckingEnabled: false,
            duckingLevel: .normal,
            inputMuted: false
        )
    )

    #expect(backend.events == [
        .setVoiceProcessingEnabled(true),
        .setAdvancedDucking(enabled: true, level: .minimum),
        .setVoiceProcessingBypassed(false),
        .setInputMuted(false),
    ])
}

@Test func voiceProcessingCanDisableProcessingWhileStillApplyingMuteState() throws {
    let backend = FakeVoiceProcessingBackend()
    let manager = AudioInputVoiceProcessingManager(backend: backend)

    try manager.configure(
        AudioInputVoiceProcessingConfiguration(
            soundIsolationEnabled: false,
            otherAudioDuckingEnabled: false,
            duckingLevel: .normal,
            inputMuted: true
        )
    )

    #expect(backend.events == [
        .setVoiceProcessingEnabled(false),
        .setAdvancedDucking(enabled: false, level: .minimum),
        .setInputMuted(true),
    ])
}

@Test func systemVoiceProcessingBackendCanBeCalledWithoutInputNode() throws {
    let manager = AudioInputVoiceProcessingManager(backend: SystemAudioInputVoiceProcessingBackend())

    try manager.configure(
        AudioInputVoiceProcessingConfiguration(
            soundIsolationEnabled: true,
            otherAudioDuckingEnabled: true,
            duckingLevel: .normal,
            inputMuted: true
        )
    )

    #expect(manager.configuration.inputMuted)
    #expect(manager.configuration.otherAudioDuckingEnabled)
}

@Test func systemSessionBackendIgnoresPlatformSpecificSelections() throws {
    let backend = SystemAudioSessionBackend()

    #if os(macOS)
    try backend.setPreferredInput(.builtInSpeaker)
    try backend.setPreferredInput(.builtInReceiver)
    try backend.setPreferredOutput(.builtInSpeaker)
    try backend.setPreferredOutput(.builtInReceiver)
    #elseif os(iOS)
    try backend.setPreferredOutput(.device("external-output"))
    #endif
}

private final class FakeAudioSessionBackend: AudioSessionBackend {
    enum Event: Equatable {
        case applyConfiguration
        case setActive(Bool)
        case setPreferredInput(AudioSessionDevice.ID?)
        case setPreferredOutput(AudioSessionDevice.ID?)
        case setPrefersEchoCancelledInput(Bool)
    }

    var events: [Event] = []
    var appliedConfigurations: [ResolvedAudioSessionConfiguration] = []
    var snapshot = AudioSessionSnapshot(
        isActive: false,
        availableInputs: [.systemDefaultInput],
        availableOutputs: [.systemDefaultOutput],
        currentInput: .systemDefaultInput,
        currentOutput: .systemDefaultOutput
    )

    func apply(_ configuration: ResolvedAudioSessionConfiguration) throws {
        events.append(.applyConfiguration)
        appliedConfigurations.append(configuration)
    }

    func setActive(_ active: Bool) throws {
        events.append(.setActive(active))
        snapshot.isActive = active
    }

    func setPreferredInput(_ selection: AudioSessionDeviceSelection) throws {
        events.append(.setPreferredInput(selection.deviceID))
    }

    func setPreferredOutput(_ selection: AudioSessionDeviceSelection) throws {
        events.append(.setPreferredOutput(selection.deviceID))
    }

    func setPrefersEchoCancelledInput(_ enabled: Bool) throws {
        events.append(.setPrefersEchoCancelledInput(enabled))
    }

    func currentSnapshot() throws -> AudioSessionSnapshot {
        snapshot
    }
}

private final class FakeVoiceProcessingBackend: AudioInputVoiceProcessingBackend {
    enum Event: Equatable {
        case setVoiceProcessingEnabled(Bool)
        case setVoiceProcessingBypassed(Bool)
        case setAdvancedDucking(enabled: Bool, level: AudioSessionDuckingLevel)
        case setInputMuted(Bool)
    }

    var events: [Event] = []

    func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        events.append(.setVoiceProcessingEnabled(enabled))
    }

    func setVoiceProcessingBypassed(_ bypassed: Bool) throws {
        events.append(.setVoiceProcessingBypassed(bypassed))
    }

    func setAdvancedDucking(enabled: Bool, level: AudioSessionDuckingLevel) throws {
        events.append(.setAdvancedDucking(enabled: enabled, level: level))
    }

    func setInputMuted(_ muted: Bool) throws {
        events.append(.setInputMuted(muted))
    }
}
