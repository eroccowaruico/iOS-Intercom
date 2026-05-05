import CryptoKit
import AVFoundation
import Codec
import Foundation
import Observation
import OSLog
import RTC
import SessionManager
import VADGate

struct AudioPortInfo: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    nonisolated static let systemDefault = AudioPortInfo(id: "__system_default__", name: "Auto")
    nonisolated static let receiver = AudioPortInfo(id: "__receiver__", name: "Receiver")
    nonisolated static let speaker = AudioPortInfo(id: "__speaker__", name: "Speaker")
}

extension AudioPortInfo {
    var sessionManagerInputSelection: SessionManager.AudioSessionDeviceSelection {
        if id == Self.systemDefault.id {
            .systemDefault
        } else {
            .device(.init(rawValue: id))
        }
    }

    var sessionManagerOutputSelection: SessionManager.AudioSessionDeviceSelection {
        switch id {
        case Self.systemDefault.id:
            .systemDefault
        case Self.speaker.id:
            .builtInSpeaker
        case Self.receiver.id:
            .builtInReceiver
        default:
            .device(.init(rawValue: id))
        }
    }
}

typealias AudioSessionConfiguration = SessionManager.AudioSessionConfiguration

extension SessionManager.AudioSessionConfiguration {
    static func intercom(
        prefersSpeakerOutput: Bool = false,
        preferredInput: SessionManager.AudioSessionDeviceSelection = .systemDefault,
        preferredOutput: SessionManager.AudioSessionDeviceSelection = .systemDefault
    ) -> AudioSessionConfiguration {
        AudioSessionConfiguration(
            mode: .default,
            defaultToSpeaker: prefersSpeakerOutput,
            prefersEchoCancelledInput: false,
            preferredInput: preferredInput,
            preferredOutput: preferredOutput
        )
    }

    static func audioCheck(
        prefersSpeakerOutput: Bool = false,
        preferredInput: SessionManager.AudioSessionDeviceSelection = .systemDefault,
        preferredOutput: SessionManager.AudioSessionDeviceSelection = .systemDefault
    ) -> AudioSessionConfiguration {
        AudioSessionConfiguration(
            mode: .default,
            defaultToSpeaker: prefersSpeakerOutput,
            prefersEchoCancelledInput: false,
            preferredInput: preferredInput,
            preferredOutput: preferredOutput
        )
    }
}

protocol AudioSessionApplying: AnyObject {
    func apply(_ configuration: AudioSessionConfiguration) throws
    func setActive(_ active: Bool) throws
    var availableInputPorts: [AudioPortInfo] { get }
    var availableOutputPorts: [AudioPortInfo] { get }
    var currentInputPort: AudioPortInfo { get }
    var currentOutputPort: AudioPortInfo { get }
    func setPreferredInputPort(_ port: AudioPortInfo) throws
    func setPreferredOutputPort(_ port: AudioPortInfo) throws
    func setAvailablePortsChangedHandler(_ handler: (() -> Void)?)
}

extension AudioSessionApplying {
    var availableInputPorts: [AudioPortInfo] { [.systemDefault] }
    var availableOutputPorts: [AudioPortInfo] { [.systemDefault] }
    var currentInputPort: AudioPortInfo { .systemDefault }
    var currentOutputPort: AudioPortInfo { .systemDefault }
    func setPreferredInputPort(_ port: AudioPortInfo) throws {}
    func setPreferredOutputPort(_ port: AudioPortInfo) throws {}
    func setAvailablePortsChangedHandler(_ handler: (() -> Void)?) {}
}


final class AudioSessionManager {
    private enum ConfigurationKind {
        case intercom
        case audioCheck
    }

    private let session: AudioSessionApplying
    private(set) var isConfigured = false
    private(set) var selectedInputPort: AudioPortInfo = .systemDefault
    private(set) var selectedOutputPort: AudioPortInfo = .systemDefault
    private(set) var isDuckOthersEnabled = false
    var onAvailablePortsChanged: (() -> Void)?
    var supportsAdvancedMixingOptions: Bool {
        true
    }
    private var currentConfigurationKind: ConfigurationKind?

    var availableInputPorts: [AudioPortInfo] { session.availableInputPorts }
    var availableOutputPorts: [AudioPortInfo] { session.availableOutputPorts }

    init(session: AudioSessionApplying = SystemAudioSessionAdapter()) {
        self.session = session
        self.session.setAvailablePortsChangedHandler { [weak self] in
            self?.handleAvailablePortsChanged()
        }
    }

    func configureForIntercom() throws {
        try configure(.intercom)
    }

    func configureForAudioCheck() throws {
        try configure(.audioCheck)
    }

    func setInputPort(_ port: AudioPortInfo) throws {
        selectedInputPort = port
        guard isConfigured else { return }
        try reapplyConfigurationIfNeeded()
    }

    func setOutputPort(_ port: AudioPortInfo) throws {
        selectedOutputPort = port
        guard isConfigured else { return }
        try reapplyConfigurationIfNeeded()
    }

    func setDuckOthersEnabled(_ enabled: Bool) throws {
        guard supportsAdvancedMixingOptions else {
            isDuckOthersEnabled = false
            return
        }

        isDuckOthersEnabled = enabled
    }

    func deactivate() throws {
        try session.setActive(false)
        isConfigured = false
        currentConfigurationKind = nil
    }

    private func configure(_ kind: ConfigurationKind) throws {
        if isConfigured, currentConfigurationKind == kind {
            try session.apply(makeConfiguration(for: kind))
            return
        }
        currentConfigurationKind = kind
        try session.apply(makeConfiguration(for: kind))
        try session.setActive(true)
        isConfigured = true
    }

    private func reapplyConfigurationIfNeeded() throws {
        guard isConfigured, let currentConfigurationKind else { return }
        try session.apply(makeConfiguration(for: currentConfigurationKind))
    }

    private func makeConfiguration(for kind: ConfigurationKind) -> AudioSessionConfiguration {
        switch kind {
        case .intercom:
            AudioSessionConfiguration.intercom(
                prefersSpeakerOutput: selectedOutputPort == .speaker,
                preferredInput: selectedInputPort.sessionManagerInputSelection,
                preferredOutput: selectedOutputPort.sessionManagerOutputSelection
            )
        case .audioCheck:
            AudioSessionConfiguration.audioCheck(
                prefersSpeakerOutput: selectedOutputPort == .speaker,
                preferredInput: selectedInputPort.sessionManagerInputSelection,
                preferredOutput: selectedOutputPort.sessionManagerOutputSelection
            )
        }
    }

    private func handleAvailablePortsChanged() {
        let inputPorts = session.availableInputPorts
        let outputPorts = session.availableOutputPorts
        let currentInputPort = session.currentInputPort
        let currentOutputPort = session.currentOutputPort

        if selectedInputPort == .systemDefault {
            selectedInputPort = .systemDefault
        } else if !inputPorts.contains(selectedInputPort) {
            selectedInputPort = .systemDefault
            if isConfigured {
                try? session.setPreferredInputPort(.systemDefault)
            }
        } else if isConfigured, currentInputPort != selectedInputPort {
            try? session.setPreferredInputPort(selectedInputPort)
        }

        if selectedOutputPort == .systemDefault {
            selectedOutputPort = .systemDefault
        } else if !outputPorts.contains(selectedOutputPort) {
            selectedOutputPort = .systemDefault
            if isConfigured {
                try? session.setPreferredOutputPort(.systemDefault)
            }
        } else if isConfigured, currentOutputPort != selectedOutputPort {
            try? session.setPreferredOutputPort(selectedOutputPort)
        }

        onAvailablePortsChanged?()
    }
}

protocol AudioInputMonitoring: AnyObject {
    var onLevel: ((Float) -> Void)? { get set }
    var onSamples: (([Float]) -> Void)? { get set }

    func start() throws
    func stop()
    func setInputMuted(_ muted: Bool)
    var supportsSoundIsolation: Bool { get }
    var isSoundIsolationEnabled: Bool { get }
    func setSoundIsolationEnabled(_ enabled: Bool)
    var supportsOtherAudioDucking: Bool { get }
    func setOtherAudioDuckingEnabled(_ enabled: Bool)
}

extension AudioInputMonitoring {
    func setInputMuted(_ muted: Bool) {}
    var supportsSoundIsolation: Bool { false }
    var isSoundIsolationEnabled: Bool { false }
    func setSoundIsolationEnabled(_ enabled: Bool) {}
    var supportsOtherAudioDucking: Bool { false }
    func setOtherAudioDuckingEnabled(_ enabled: Bool) {}
}

enum MicrophoneAuthorizationState: Equatable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

protocol MicrophonePermissionAuthorizing {
    func authorizationState() -> MicrophoneAuthorizationState
    func requestAccess(completion: @escaping (Bool) -> Void)
}

enum AudioInputMonitorError: Error, Equatable {
    case microphonePermissionRequestPending
    case microphonePermissionDenied
}

protocol CallTicking: AnyObject {
    var onTick: ((TimeInterval) -> Void)? { get set }

    func start()
    func stop()
}

final class RepeatingCallTicker: CallTicking {
    var onTick: ((TimeInterval) -> Void)?
    private let interval: Duration
    private var task: Task<Void, Never>?

    init(interval: Duration = .milliseconds(10)) {
        self.interval = interval
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.interval ?? .milliseconds(10))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.onTick?(Date().timeIntervalSince1970)
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

