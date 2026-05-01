import Foundation

#if canImport(AVFAudio)
@preconcurrency import AVFAudio
#endif

#if os(macOS)
import CoreAudio
#endif

public enum AudioSessionManagerError: Error, Equatable, Sendable {
    case echoCancelledInputRequiresDefaultMode
    case inputSelectionUnsupported(AudioSessionDeviceSelection)
    case outputSelectionUnsupported(AudioSessionDeviceSelection)
    case deviceNotFound(AudioSessionDevice.ID)
    case coreAudioOperationFailed(String)
}

public enum AudioSessionDuckingLevel: Equatable, Sendable {
    case minimum
    case normal
}

public enum AudioSessionCategory: Equatable, Sendable {
    case playAndRecord
}

public enum AudioSessionMode: Equatable, Sendable {
    case `default`
    case voiceChat
}

public enum AudioSessionCategoryOption: Equatable, Hashable, Sendable {
    case allowBluetoothA2DP
    case allowBluetoothHFP
    case bluetoothHighQualityRecording
    case defaultToSpeaker
    case duckOthers
    case farFieldInput
    case mixWithOthers
    case overrideMutedMicrophoneInterruption
}

public struct AudioSessionDevice: Equatable, Hashable, Sendable, Identifiable {
    public struct ID: RawRepresentable, Equatable, Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: StringLiteralType) {
            rawValue = value
        }
    }

    public enum Direction: Equatable, Sendable {
        case input
        case output
    }

    public var id: ID
    public var name: String
    public var direction: Direction
    public var isSystemDefault: Bool

    public init(id: ID, name: String, direction: Direction, isSystemDefault: Bool = false) {
        self.id = id
        self.name = name
        self.direction = direction
        self.isSystemDefault = isSystemDefault
    }

    public static let systemDefaultInput = AudioSessionDevice(
        id: "system-default-input",
        name: "System Default Input",
        direction: .input,
        isSystemDefault: true
    )

    public static let systemDefaultOutput = AudioSessionDevice(
        id: "system-default-output",
        name: "System Default Output",
        direction: .output,
        isSystemDefault: true
    )

    public static let builtInSpeaker = AudioSessionDevice(
        id: "built-in-speaker",
        name: "Built-in Speaker",
        direction: .output
    )

    public static let builtInReceiver = AudioSessionDevice(
        id: "built-in-receiver",
        name: "Built-in Receiver",
        direction: .output
    )
}

public enum AudioSessionDeviceSelection: Equatable, Sendable {
    case systemDefault
    case builtInSpeaker
    case builtInReceiver
    case device(AudioSessionDevice.ID)

    public var deviceID: AudioSessionDevice.ID? {
        switch self {
        case .systemDefault:
            nil
        case .builtInSpeaker:
            AudioSessionDevice.builtInSpeaker.id
        case .builtInReceiver:
            AudioSessionDevice.builtInReceiver.id
        case .device(let deviceID):
            deviceID
        }
    }
}

public struct AudioSessionConfiguration: Equatable, Sendable {
    public var mode: AudioSessionMode
    public var defaultToSpeaker: Bool
    public var prefersEchoCancelledInput: Bool
    public var preferredInput: AudioSessionDeviceSelection
    public var preferredOutput: AudioSessionDeviceSelection

    public init(
        mode: AudioSessionMode = .default,
        defaultToSpeaker: Bool = false,
        prefersEchoCancelledInput: Bool = false,
        preferredInput: AudioSessionDeviceSelection = .systemDefault,
        preferredOutput: AudioSessionDeviceSelection = .systemDefault
    ) {
        self.mode = mode
        self.defaultToSpeaker = defaultToSpeaker
        self.prefersEchoCancelledInput = prefersEchoCancelledInput
        self.preferredInput = preferredInput
        self.preferredOutput = preferredOutput
    }

    public func resolved() throws -> ResolvedAudioSessionConfiguration {
        if mode == .voiceChat && prefersEchoCancelledInput {
            throw AudioSessionManagerError.echoCancelledInputRequiresDefaultMode
        }

        var options: Set<AudioSessionCategoryOption> = [
            .allowBluetoothA2DP,
            .allowBluetoothHFP,
            .bluetoothHighQualityRecording,
            .duckOthers,
            .farFieldInput,
            .mixWithOthers,
            .overrideMutedMicrophoneInterruption,
        ]

        if defaultToSpeaker {
            options.insert(.defaultToSpeaker)
        }

        return ResolvedAudioSessionConfiguration(
            category: .playAndRecord,
            mode: mode,
            options: options,
            prefersEchoCancelledInput: mode == .default ? prefersEchoCancelledInput : nil,
            preferredInput: preferredInput,
            preferredOutput: preferredOutput
        )
    }
}

public struct ResolvedAudioSessionConfiguration: Equatable, Sendable {
    public var category: AudioSessionCategory
    public var mode: AudioSessionMode
    public var options: Set<AudioSessionCategoryOption>
    public var prefersEchoCancelledInput: Bool?
    public var preferredInput: AudioSessionDeviceSelection
    public var preferredOutput: AudioSessionDeviceSelection

    public init(
        category: AudioSessionCategory,
        mode: AudioSessionMode,
        options: Set<AudioSessionCategoryOption>,
        prefersEchoCancelledInput: Bool?,
        preferredInput: AudioSessionDeviceSelection,
        preferredOutput: AudioSessionDeviceSelection
    ) {
        self.category = category
        self.mode = mode
        self.options = options
        self.prefersEchoCancelledInput = prefersEchoCancelledInput
        self.preferredInput = preferredInput
        self.preferredOutput = preferredOutput
    }
}

public struct AudioSessionSnapshot: Equatable, Sendable {
    public var isActive: Bool
    public var availableInputs: [AudioSessionDevice]
    public var availableOutputs: [AudioSessionDevice]
    public var currentInput: AudioSessionDevice
    public var currentOutput: AudioSessionDevice

    public init(
        isActive: Bool,
        availableInputs: [AudioSessionDevice],
        availableOutputs: [AudioSessionDevice],
        currentInput: AudioSessionDevice,
        currentOutput: AudioSessionDevice
    ) {
        self.isActive = isActive
        self.availableInputs = availableInputs
        self.availableOutputs = availableOutputs
        self.currentInput = currentInput
        self.currentOutput = currentOutput
    }
}

public struct AudioInputVoiceProcessingConfiguration: Equatable, Sendable {
    public var soundIsolationEnabled: Bool
    public var otherAudioDuckingEnabled: Bool
    public var duckingLevel: AudioSessionDuckingLevel
    public var inputMuted: Bool

    public init(
        soundIsolationEnabled: Bool = true,
        otherAudioDuckingEnabled: Bool = false,
        duckingLevel: AudioSessionDuckingLevel = .minimum,
        inputMuted: Bool = false
    ) {
        self.soundIsolationEnabled = soundIsolationEnabled
        self.otherAudioDuckingEnabled = otherAudioDuckingEnabled
        self.duckingLevel = duckingLevel
        self.inputMuted = inputMuted
    }

    public var voiceProcessingEnabled: Bool {
        soundIsolationEnabled || otherAudioDuckingEnabled
    }

    public var voiceProcessingBypassed: Bool {
        !soundIsolationEnabled
    }

    public var resolvedDuckingLevel: AudioSessionDuckingLevel {
        otherAudioDuckingEnabled ? duckingLevel : .minimum
    }
}

public protocol AudioSessionBackend: AnyObject {
    func apply(_ configuration: ResolvedAudioSessionConfiguration) throws
    func setActive(_ active: Bool) throws
    func setPreferredInput(_ selection: AudioSessionDeviceSelection) throws
    func setPreferredOutput(_ selection: AudioSessionDeviceSelection) throws
    func setPrefersEchoCancelledInput(_ enabled: Bool) throws
    func currentSnapshot() throws -> AudioSessionSnapshot
}

public protocol AudioInputVoiceProcessingBackend: AnyObject {
    func setVoiceProcessingEnabled(_ enabled: Bool) throws
    func setVoiceProcessingBypassed(_ bypassed: Bool) throws
    func setAdvancedDucking(enabled: Bool, level: AudioSessionDuckingLevel) throws
    func setInputMuted(_ muted: Bool) throws
}

public final class AudioSessionManager {
    private let backend: AudioSessionBackend
    public private(set) var configuration: AudioSessionConfiguration
    public private(set) var resolvedConfiguration: ResolvedAudioSessionConfiguration

    public convenience init() {
        self.init(backend: SystemAudioSessionBackend())
    }

    public init(configuration: AudioSessionConfiguration = AudioSessionConfiguration(), backend: AudioSessionBackend) {
        self.configuration = configuration
        self.resolvedConfiguration = try! configuration.resolved()
        self.backend = backend
    }

    public func configure(_ configuration: AudioSessionConfiguration) throws {
        let resolved = try configuration.resolved()
        try backend.apply(resolved)
        try backend.setPreferredInput(resolved.preferredInput)
        try backend.setPreferredOutput(resolved.preferredOutput)
        if let prefersEchoCancelledInput = resolved.prefersEchoCancelledInput {
            try backend.setPrefersEchoCancelledInput(prefersEchoCancelledInput)
        }
        self.configuration = configuration
        resolvedConfiguration = resolved
    }

    public func setActive(_ active: Bool) throws {
        try backend.setActive(active)
    }

    public func snapshot() throws -> AudioSessionSnapshot {
        try backend.currentSnapshot()
    }
}

public final class AudioInputVoiceProcessingManager {
    private let backend: AudioInputVoiceProcessingBackend
    public private(set) var configuration: AudioInputVoiceProcessingConfiguration

    public init(
        configuration: AudioInputVoiceProcessingConfiguration = AudioInputVoiceProcessingConfiguration(),
        backend: AudioInputVoiceProcessingBackend
    ) {
        self.configuration = configuration
        self.backend = backend
    }

    public func configure(_ configuration: AudioInputVoiceProcessingConfiguration) throws {
        try backend.setVoiceProcessingEnabled(configuration.voiceProcessingEnabled)
        if configuration.voiceProcessingEnabled {
            try backend.setAdvancedDucking(enabled: true, level: configuration.resolvedDuckingLevel)
            try backend.setVoiceProcessingBypassed(configuration.voiceProcessingBypassed)
        } else {
            try backend.setAdvancedDucking(enabled: false, level: .minimum)
        }
        try backend.setInputMuted(configuration.inputMuted)
        self.configuration = configuration
    }

    public func setInputMuted(_ muted: Bool) throws {
        var updated = configuration
        updated.inputMuted = muted
        try configure(updated)
    }

    public func setOtherAudioDucking(enabled: Bool, level: AudioSessionDuckingLevel) throws {
        var updated = configuration
        updated.otherAudioDuckingEnabled = enabled
        updated.duckingLevel = level
        try configure(updated)
    }
}

public final class SystemAudioSessionBackend: AudioSessionBackend {
    #if os(iOS)
    private let session: AVAudioSession

    public init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }
    #else
    public init() {}
    #endif

    public func apply(_ configuration: ResolvedAudioSessionConfiguration) throws {
        #if os(iOS)
        try session.setCategory(
            configuration.category.avCategory,
            mode: configuration.mode.avMode,
            options: configuration.options.avCategoryOptions
        )
        #else
        _ = configuration
        #endif
    }

    public func setActive(_ active: Bool) throws {
        #if os(iOS)
        if active {
            try session.setActive(true)
        } else {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        }
        #else
        _ = active
        #endif
    }

    public func setPreferredInput(_ selection: AudioSessionDeviceSelection) throws {
        #if os(iOS)
        switch selection {
        case .systemDefault:
            try session.setPreferredInput(nil)
        case .device(let deviceID):
            guard let port = session.availableInputs?.first(where: { $0.uid == deviceID.rawValue }) else {
                throw AudioSessionManagerError.deviceNotFound(deviceID)
            }
            try session.setPreferredInput(port)
        case .builtInSpeaker, .builtInReceiver:
            throw AudioSessionManagerError.inputSelectionUnsupported(selection)
        }
        #elseif os(macOS)
        switch selection {
        case .systemDefault:
            return
        case .device(let deviceID):
            try setDefaultMacDevice(deviceID, selector: kAudioHardwarePropertyDefaultInputDevice)
        case .builtInSpeaker, .builtInReceiver:
            return
        }
        #else
        _ = selection
        #endif
    }

    public func setPreferredOutput(_ selection: AudioSessionDeviceSelection) throws {
        #if os(iOS)
        switch selection {
        case .systemDefault, .builtInReceiver:
            try session.overrideOutputAudioPort(.none)
        case .builtInSpeaker:
            try session.overrideOutputAudioPort(.speaker)
        case .device:
            return
        }
        #elseif os(macOS)
        switch selection {
        case .systemDefault:
            return
        case .device(let deviceID):
            try setDefaultMacDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
        case .builtInSpeaker, .builtInReceiver:
            return
        }
        #else
        _ = selection
        #endif
    }

    public func setPrefersEchoCancelledInput(_ enabled: Bool) throws {
        #if os(iOS)
        try session.setPrefersEchoCancelledInput(enabled)
        #else
        _ = enabled
        #endif
    }

    public func currentSnapshot() throws -> AudioSessionSnapshot {
        #if os(iOS)
        return AudioSessionSnapshot(
            isActive: !session.currentRoute.inputs.isEmpty || !session.currentRoute.outputs.isEmpty,
            availableInputs: iOSAvailableInputs(),
            availableOutputs: [.systemDefaultOutput, .builtInReceiver, .builtInSpeaker],
            currentInput: session.currentRoute.inputs.first.map { AudioSessionDevice(id: .init(rawValue: $0.uid), name: $0.portName, direction: .input) } ?? .systemDefaultInput,
            currentOutput: iOSCurrentOutput()
        )
        #elseif os(macOS)
        let inputs = macDevices(scope: kAudioDevicePropertyScopeInput)
        let outputs = macDevices(scope: kAudioDevicePropertyScopeOutput)
        return AudioSessionSnapshot(
            isActive: true,
            availableInputs: [.systemDefaultInput] + inputs,
            availableOutputs: [.systemDefaultOutput] + outputs,
            currentInput: currentMacDevice(selector: kAudioHardwarePropertyDefaultInputDevice, direction: .input) ?? .systemDefaultInput,
            currentOutput: currentMacDevice(selector: kAudioHardwarePropertyDefaultOutputDevice, direction: .output) ?? .systemDefaultOutput
        )
        #else
        return AudioSessionSnapshot(
            isActive: false,
            availableInputs: [.systemDefaultInput],
            availableOutputs: [.systemDefaultOutput],
            currentInput: .systemDefaultInput,
            currentOutput: .systemDefaultOutput
        )
        #endif
    }
}

public final class SystemAudioInputVoiceProcessingBackend: AudioInputVoiceProcessingBackend {
    #if canImport(AVFAudio)
    private let inputNode: AVAudioInputNode?

    public init(inputNode: AVAudioInputNode? = nil) {
        self.inputNode = inputNode
    }
    #else
    public init() {}
    #endif

    public func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        #if os(iOS)
        guard let inputNode else { return }
        if inputNode.isVoiceProcessingEnabled != enabled {
            try inputNode.setVoiceProcessingEnabled(enabled)
        }
        #else
        _ = enabled
        #endif
    }

    public func setVoiceProcessingBypassed(_ bypassed: Bool) throws {
        #if os(iOS)
        guard let inputNode else { return }
        inputNode.isVoiceProcessingBypassed = bypassed
        #else
        _ = bypassed
        #endif
    }

    public func setAdvancedDucking(enabled: Bool, level: AudioSessionDuckingLevel) throws {
        #if os(iOS)
        guard let inputNode else { return }
        inputNode.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
            enableAdvancedDucking: ObjCBool(enabled),
            duckingLevel: level.avDuckingLevel
        )
        #else
        _ = enabled
        _ = level
        #endif
    }

    public func setInputMuted(_ muted: Bool) throws {
        #if os(iOS)
        guard let inputNode else { return }
        inputNode.isVoiceProcessingInputMuted = muted
        #else
        _ = muted
        #endif
    }
}

#if os(iOS)
private extension AudioSessionCategory {
    var avCategory: AVAudioSession.Category {
        switch self {
        case .playAndRecord:
            .playAndRecord
        }
    }
}

private extension AudioSessionMode {
    var avMode: AVAudioSession.Mode {
        switch self {
        case .default:
            .default
        case .voiceChat:
            .voiceChat
        }
    }
}

private extension Set where Element == AudioSessionCategoryOption {
    var avCategoryOptions: AVAudioSession.CategoryOptions {
        var mapped: AVAudioSession.CategoryOptions = []
        if contains(.allowBluetoothA2DP) { mapped.insert(.allowBluetoothA2DP) }
        if contains(.allowBluetoothHFP) { mapped.insert(.allowBluetoothHFP) }
        if contains(.bluetoothHighQualityRecording) { mapped.insert(.bluetoothHighQualityRecording) }
        if contains(.defaultToSpeaker) { mapped.insert(.defaultToSpeaker) }
        if contains(.duckOthers) { mapped.insert(.duckOthers) }
        if contains(.farFieldInput) { mapped.insert(.farFieldInput) }
        if contains(.mixWithOthers) { mapped.insert(.mixWithOthers) }
        if contains(.overrideMutedMicrophoneInterruption) { mapped.insert(.overrideMutedMicrophoneInterruption) }
        return mapped
    }
}

private extension AudioSessionDuckingLevel {
    var avDuckingLevel: AVAudioVoiceProcessingOtherAudioDuckingConfiguration.Level {
        switch self {
        case .minimum:
            .min
        case .normal:
            .default
        }
    }
}

private extension SystemAudioSessionBackend {
    func iOSAvailableInputs() -> [AudioSessionDevice] {
        [.systemDefaultInput] + (session.availableInputs ?? []).map {
            AudioSessionDevice(id: .init(rawValue: $0.uid), name: $0.portName, direction: .input)
        }
    }

    func iOSCurrentOutput() -> AudioSessionDevice {
        guard let output = session.currentRoute.outputs.first else { return .systemDefaultOutput }
        if output.portType == .builtInSpeaker {
            return .builtInSpeaker
        }
        if output.portType == .builtInReceiver {
            return .builtInReceiver
        }
        return AudioSessionDevice(id: .init(rawValue: output.uid), name: output.portName, direction: .output)
    }
}
#endif

#if os(macOS)
private extension SystemAudioSessionBackend {
    func macDevices(scope: AudioObjectPropertyScope) -> [AudioSessionDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard deviceHasStreams(deviceID, scope: scope), let name = deviceName(deviceID) else { return nil }
            let direction: AudioSessionDevice.Direction = scope == kAudioDevicePropertyScopeInput ? .input : .output
            return AudioSessionDevice(id: .init(rawValue: String(deviceID)), name: name, direction: direction)
        }
    }

    func currentMacDevice(selector: AudioObjectPropertySelector, direction: AudioSessionDevice.Direction) -> AudioSessionDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              let name = deviceName(deviceID)
        else { return nil }
        return AudioSessionDevice(id: .init(rawValue: String(deviceID)), name: name, direction: direction)
    }

    func setDefaultMacDevice(_ id: AudioSessionDevice.ID, selector: AudioObjectPropertySelector) throws {
        guard var deviceID = AudioDeviceID(id.rawValue) else {
            throw AudioSessionManagerError.deviceNotFound(id)
        }
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        guard status == noErr else {
            throw AudioSessionManagerError.coreAudioOperationFailed("AudioObjectSetPropertyData failed: \(status)")
        }
    }

    func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeUnretainedValue() as String?
    }

    func deviceHasStreams(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
    }
}
#endif
