import Foundation
import AVFAudio
import AudioMixer

final class SystemAudioOutputRenderer: AudioOutputRendering {
    private let engine: AVAudioEngine
    private var mixer: AudioMixer
    private let notificationCenter: NotificationCenter
    private let format: AVAudioFormat
    private var playerNode: AVAudioPlayerNode
    private var outputBus: MixerBus?
    private var isConfigured = false
    private var isRoutedToOutput = false
    private var configurationChangeObserver: NSObjectProtocol?
    private var shouldResumeAfterConfigurationChange = false

    init(
        engine: AVAudioEngine = AVAudioEngine(),
        playerNode: AVAudioPlayerNode = AVAudioPlayerNode(),
        notificationCenter: NotificationCenter = .default,
        sampleRate: Double = 16_000,
        channelCount: AVAudioChannelCount = 1
    ) {
        self.engine = engine
        self.playerNode = playerNode
        self.notificationCenter = notificationCenter
        self.format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!
        self.mixer = AudioMixer(engine: engine, format: format)
        configurationChangeObserver = notificationCenter.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleEngineConfigurationChange()
        }
    }

    func start() throws {
        if !isConfigured {
            try configureGraph()
        }

        try startPlaybackIfNeeded()
    }

    func stop() {
        shouldResumeAfterConfigurationChange = false
        playerNode.stop()
        mixer.stop()
    }

    func schedule(samples: [Float]) {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channelData = buffer.floatChannelData else { return }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices {
            channelData[0][index] = samples[index]
        }
        playerNode.scheduleBuffer(buffer, at: nil, options: [])
    }

    deinit {
        if let configurationChangeObserver {
            notificationCenter.removeObserver(configurationChangeObserver)
        }
    }

    private func configureGraph() throws {
        if engine.attachedNodes.contains(playerNode) {
            engine.disconnectNodeOutput(playerNode)
            engine.detach(playerNode)
        }
        let bus = try mixer.createBus("output")
        try bus.addSource(playerNode)
        if !isRoutedToOutput {
            try mixer.routeToOutput(bus)
            isRoutedToOutput = true
        }
        outputBus = bus
        isConfigured = true
    }

    private func startPlaybackIfNeeded() throws {
        if !engine.isRunning {
            try mixer.start()
        }
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func handleEngineConfigurationChange() {
        shouldResumeAfterConfigurationChange = engine.isRunning || playerNode.isPlaying || shouldResumeAfterConfigurationChange
        playerNode.stop()
        if engine.attachedNodes.contains(playerNode) {
            engine.disconnectNodeOutput(playerNode)
            engine.detach(playerNode)
        }
        if let outputBus {
            engine.disconnectNodeOutput(outputBus.inputMixer)
            engine.disconnectNodeOutput(outputBus.faderMixer)
            engine.disconnectNodeInput(outputBus.inputMixer)
            engine.disconnectNodeInput(outputBus.faderMixer)
            engine.detach(outputBus.inputMixer)
            engine.detach(outputBus.faderMixer)
        }
        engine.stop()
        engine.reset()
        mixer = AudioMixer(engine: engine, format: format)
        playerNode = AVAudioPlayerNode()
        outputBus = nil
        isRoutedToOutput = false
        isConfigured = false
        try? configureGraph()
        guard shouldResumeAfterConfigurationChange else { return }
        try? startPlaybackIfNeeded()
    }
}
