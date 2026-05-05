import Foundation
import AVFAudio
import SessionManager

#if os(macOS)
import CoreAudio
#endif

final class SystemAudioSessionAdapter: AudioSessionApplying {
    private let sessionManager: SessionManager.AudioSessionManager
    private var onAvailablePortsChanged: (() -> Void)?
    private var configuration = AudioSessionConfiguration()

    #if os(iOS)
    private let notificationCenter: NotificationCenter
    private var routeChangeObserver: NSObjectProtocol?

    init(
        backend: SessionManager.SystemAudioSessionBackend = SessionManager.SystemAudioSessionBackend(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.sessionManager = SessionManager.AudioSessionManager(backend: backend)
        self.notificationCenter = notificationCenter
    }
    #else
    private let coreAudioListenerQueue = DispatchQueue(label: "RideIntercom.SystemAudioSessionAdapter.CoreAudio")
    private var coreAudioPropertyListener: AudioObjectPropertyListenerBlock?

    init(backend: SessionManager.SystemAudioSessionBackend = SessionManager.SystemAudioSessionBackend()) {
        self.sessionManager = SessionManager.AudioSessionManager(backend: backend)
    }
    #endif

    func apply(_ configuration: AudioSessionConfiguration) throws {
        self.configuration = configuration
        try sessionManager.configure(configuration)
    }

    func setActive(_ active: Bool) throws {
        try sessionManager.setActive(active)
    }

    var availableInputPorts: [AudioPortInfo] {
        snapshot().availableInputs.map(AudioPortInfo.init(sessionDevice:)).deduplicatedWithSystemDefault()
    }

    var availableOutputPorts: [AudioPortInfo] {
        snapshot().availableOutputs.map(AudioPortInfo.init(sessionDevice:)).deduplicatedWithSystemDefault()
    }

    var currentInputPort: AudioPortInfo {
        AudioPortInfo(sessionDevice: snapshot().currentInput)
    }

    var currentOutputPort: AudioPortInfo {
        AudioPortInfo(sessionDevice: snapshot().currentOutput)
    }

    func setPreferredInputPort(_ port: AudioPortInfo) throws {
        configuration.preferredInput = port.sessionManagerInputSelection
        try sessionManager.configure(configuration)
    }

    func setPreferredOutputPort(_ port: AudioPortInfo) throws {
        configuration.preferredOutput = port.sessionManagerOutputSelection
        configuration.defaultToSpeaker = port == .speaker
        try sessionManager.configure(configuration)
    }

    func setAvailablePortsChangedHandler(_ handler: (() -> Void)?) {
        onAvailablePortsChanged = handler
        #if os(iOS)
        if let routeChangeObserver {
            notificationCenter.removeObserver(routeChangeObserver)
            self.routeChangeObserver = nil
        }
        guard handler != nil else { return }
        routeChangeObserver = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onAvailablePortsChanged?()
        }
        #elseif os(macOS)
        removeCoreAudioListeners()
        guard handler != nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.onAvailablePortsChanged?()
            }
        }
        coreAudioPropertyListener = listener
        addCoreAudioListener(selector: kAudioHardwarePropertyDevices, listener: listener)
        addCoreAudioListener(selector: kAudioHardwarePropertyDefaultInputDevice, listener: listener)
        addCoreAudioListener(selector: kAudioHardwarePropertyDefaultOutputDevice, listener: listener)
        #endif
    }

    deinit {
        #if os(iOS)
        if let routeChangeObserver {
            notificationCenter.removeObserver(routeChangeObserver)
        }
        #elseif os(macOS)
        removeCoreAudioListeners()
        #endif
    }

    private func snapshot() -> SessionManager.AudioSessionSnapshot {
        (try? sessionManager.snapshot()) ?? SessionManager.AudioSessionSnapshot(
            isActive: false,
            availableInputs: [.systemDefaultInput],
            availableOutputs: [.systemDefaultOutput],
            currentInput: .systemDefaultInput,
            currentOutput: .systemDefaultOutput
        )
    }
}

private extension AudioPortInfo {
    nonisolated init(sessionDevice device: SessionManager.AudioSessionDevice) {
        if device == .systemDefaultInput || device == .systemDefaultOutput {
            self = .systemDefault
        } else if device == .builtInSpeaker {
            self = .speaker
        } else if device == .builtInReceiver {
            self = .receiver
        } else {
            self = AudioPortInfo(id: device.id.rawValue, name: device.name)
        }
    }

}

private extension Array where Element == AudioPortInfo {
    func deduplicatedWithSystemDefault() -> [AudioPortInfo] {
        var result: [AudioPortInfo] = []
        for port in self {
            guard !result.contains(port) else { continue }
            result.append(port)
        }
        return result.isEmpty ? [.systemDefault] : result
    }
}

#if os(macOS)
private extension SystemAudioSessionAdapter {
    func addCoreAudioListener(
        selector: AudioObjectPropertySelector,
        listener: @escaping AudioObjectPropertyListenerBlock
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            coreAudioListenerQueue,
            listener
        )
    }

    func removeCoreAudioListeners() {
        guard let listener = coreAudioPropertyListener else { return }
        removeCoreAudioListener(selector: kAudioHardwarePropertyDevices, listener: listener)
        removeCoreAudioListener(selector: kAudioHardwarePropertyDefaultInputDevice, listener: listener)
        removeCoreAudioListener(selector: kAudioHardwarePropertyDefaultOutputDevice, listener: listener)
        coreAudioPropertyListener = nil
    }

    func removeCoreAudioListener(
        selector: AudioObjectPropertySelector,
        listener: @escaping AudioObjectPropertyListenerBlock
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            coreAudioListenerQueue,
            listener
        )
    }
}
#endif
