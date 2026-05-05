import Foundation

#if canImport(AVFAudio)
@preconcurrency import AVFAudio
#endif

public enum AudioStreamDirection: Equatable, Sendable {
    case input
    case output
}

public struct AudioStreamFormat: Equatable, Sendable {
    public var sampleRate: Double
    public var channelCount: Int

    public init(sampleRate: Double = 48_000, channelCount: Int = 1) {
        self.sampleRate = min(96_000, max(8_000, sampleRate))
        self.channelCount = min(2, max(1, channelCount))
    }
}

public struct AudioStreamLevel: Equatable, Sendable {
    public var rms: Float
    public var peak: Float

    public init(samples: [Float]) {
        guard !samples.isEmpty else {
            self.rms = 0
            self.peak = 0
            return
        }
        var sum: Float = 0
        var peak: Float = 0
        for sample in samples {
            let magnitude = abs(sample)
            sum += sample * sample
            peak = max(peak, magnitude)
        }
        self.rms = sqrt(sum / Float(samples.count))
        self.peak = peak
    }

    public init(rms: Float, peak: Float) {
        self.rms = rms
        self.peak = peak
    }
}

public struct AudioStreamFrame: Equatable, Sendable {
    public var sequenceNumber: UInt64
    public var format: AudioStreamFormat
    public var capturedAt: TimeInterval
    public var samples: [Float]
    public var level: AudioStreamLevel

    public init(
        sequenceNumber: UInt64,
        format: AudioStreamFormat = AudioStreamFormat(),
        capturedAt: TimeInterval = Date().timeIntervalSince1970,
        samples: [Float]
    ) {
        self.sequenceNumber = sequenceNumber
        self.format = format
        self.capturedAt = capturedAt
        self.samples = samples
        self.level = AudioStreamLevel(samples: samples)
    }
}

public struct AudioInputStreamConfiguration: Equatable, Sendable {
    public var format: AudioStreamFormat
    public var bufferFrameCount: UInt32
    public var voiceProcessing: AudioInputVoiceProcessingConfiguration

    public init(
        format: AudioStreamFormat = AudioStreamFormat(),
        bufferFrameCount: UInt32 = 128,
        voiceProcessing: AudioInputVoiceProcessingConfiguration = AudioInputVoiceProcessingConfiguration()
    ) {
        self.format = format
        self.bufferFrameCount = max(1, bufferFrameCount)
        self.voiceProcessing = voiceProcessing
    }
}

public struct AudioOutputStreamConfiguration: Equatable, Sendable {
    public var format: AudioStreamFormat

    public init(format: AudioStreamFormat = AudioStreamFormat()) {
        self.format = format
    }
}

public struct AudioStreamSnapshot: Equatable, Sendable {
    public var direction: AudioStreamDirection
    public var isRunning: Bool
    public var format: AudioStreamFormat
    public var processedFrameCount: UInt64

    public init(
        direction: AudioStreamDirection,
        isRunning: Bool,
        format: AudioStreamFormat,
        processedFrameCount: UInt64
    ) {
        self.direction = direction
        self.isRunning = isRunning
        self.format = format
        self.processedFrameCount = processedFrameCount
    }
}

public enum AudioStreamOperation: Equatable, Sendable {
    case startInputCapture
    case stopInputCapture
    case startOutputRenderer
    case stopOutputRenderer
    case scheduleOutputFrame
}

public enum AudioStreamIgnoredReason: Equatable, Sendable {
    case alreadyRunning
    case alreadyStopped
    case unsupportedOnCurrentPlatform
}

public enum AudioStreamOperationFailure: Equatable, Sendable {
    case invalidFrame(String)
    case engineOperationFailed(String)
    case unexpected(String)
}

public enum AudioStreamOperationResult: Equatable, Sendable {
    case applied
    case ignored(AudioStreamIgnoredReason)
    case failed(AudioStreamOperationFailure)
}

public struct AudioStreamOperationReport: Equatable, Sendable {
    public var operation: AudioStreamOperation
    public var result: AudioStreamOperationResult
    public var snapshot: AudioStreamSnapshot

    public init(
        operation: AudioStreamOperation,
        result: AudioStreamOperationResult,
        snapshot: AudioStreamSnapshot
    ) {
        self.operation = operation
        self.result = result
        self.snapshot = snapshot
    }
}

public enum AudioStreamRuntimeEvent: Equatable, Sendable {
    case operation(AudioStreamOperationReport)
    case inputFrame(AudioStreamFrame)
    case outputFrameScheduled(AudioStreamFrame)
}

public typealias AudioStreamRuntimeEventHandler = (AudioStreamRuntimeEvent) -> Void

public enum AudioStreamError: Error, Equatable, Sendable {
    case unsupportedOnCurrentPlatform
    case invalidFrame(String)
    case engineOperationFailed(String)
}

public protocol AudioInputStreamBackend: AnyObject {
    func startCapture(
        configuration: AudioInputStreamConfiguration,
        onFrame: @escaping (AudioStreamFrame) -> Void
    ) throws
    func stopCapture() throws
}

public protocol AudioOutputStreamBackend: AnyObject {
    func startRendering(configuration: AudioOutputStreamConfiguration) throws
    func stopRendering() throws
    func schedule(_ frame: AudioStreamFrame) throws
}

public final class AudioInputStreamCapture {
    private let backend: AudioInputStreamBackend
    private var runtimeEventHandler: AudioStreamRuntimeEventHandler?
    private var isRunning = false
    private var capturedFrameCount: UInt64 = 0
    public private(set) var configuration: AudioInputStreamConfiguration

    public init(
        configuration: AudioInputStreamConfiguration = AudioInputStreamConfiguration(),
        backend: AudioInputStreamBackend
    ) {
        self.configuration = configuration
        self.backend = backend
    }

    #if canImport(AVFAudio)
    public convenience init(
        configuration: AudioInputStreamConfiguration = AudioInputStreamConfiguration(),
        engine: AVAudioEngine = AVAudioEngine()
    ) {
        self.init(
            configuration: configuration,
            backend: SystemAudioInputStreamBackend(engine: engine)
        )
    }
    #endif

    public func setRuntimeEventHandler(_ handler: AudioStreamRuntimeEventHandler?) {
        runtimeEventHandler = handler
    }

    @discardableResult
    public func start() -> AudioStreamOperationReport {
        guard !isRunning else {
            return emitReport(.startInputCapture, .ignored(.alreadyRunning))
        }
        do {
            try backend.startCapture(configuration: configuration) { [weak self] frame in
                self?.handleCapturedFrame(frame)
            }
            isRunning = true
            return emitReport(.startInputCapture, .applied)
        } catch {
            return emitReport(.startInputCapture, Self.operationResult(for: error))
        }
    }

    @discardableResult
    public func stop() -> AudioStreamOperationReport {
        guard isRunning else {
            return emitReport(.stopInputCapture, .ignored(.alreadyStopped))
        }
        do {
            try backend.stopCapture()
            isRunning = false
            return emitReport(.stopInputCapture, .applied)
        } catch {
            return emitReport(.stopInputCapture, Self.operationResult(for: error))
        }
    }

    private func handleCapturedFrame(_ frame: AudioStreamFrame) {
        capturedFrameCount += 1
        runtimeEventHandler?(.inputFrame(frame))
    }

    private func snapshot() -> AudioStreamSnapshot {
        AudioStreamSnapshot(
            direction: .input,
            isRunning: isRunning,
            format: configuration.format,
            processedFrameCount: capturedFrameCount
        )
    }

    private func emitReport(
        _ operation: AudioStreamOperation,
        _ result: AudioStreamOperationResult
    ) -> AudioStreamOperationReport {
        let report = AudioStreamOperationReport(
            operation: operation,
            result: result,
            snapshot: snapshot()
        )
        runtimeEventHandler?(.operation(report))
        return report
    }
}

public final class AudioOutputStreamRenderer {
    private let backend: AudioOutputStreamBackend
    private var runtimeEventHandler: AudioStreamRuntimeEventHandler?
    private var isRunning = false
    private var scheduledFrameCount: UInt64 = 0
    public private(set) var configuration: AudioOutputStreamConfiguration

    public init(
        configuration: AudioOutputStreamConfiguration = AudioOutputStreamConfiguration(),
        backend: AudioOutputStreamBackend
    ) {
        self.configuration = configuration
        self.backend = backend
    }

    #if canImport(AVFAudio)
    public convenience init(
        configuration: AudioOutputStreamConfiguration = AudioOutputStreamConfiguration(),
        engine: AVAudioEngine = AVAudioEngine(),
        playerNode: AVAudioPlayerNode = AVAudioPlayerNode()
    ) {
        self.init(
            configuration: configuration,
            backend: SystemAudioOutputStreamBackend(engine: engine, playerNode: playerNode)
        )
    }
    #endif

    public func setRuntimeEventHandler(_ handler: AudioStreamRuntimeEventHandler?) {
        runtimeEventHandler = handler
    }

    @discardableResult
    public func start() -> AudioStreamOperationReport {
        guard !isRunning else {
            return emitReport(.startOutputRenderer, .ignored(.alreadyRunning))
        }
        do {
            try backend.startRendering(configuration: configuration)
            isRunning = true
            return emitReport(.startOutputRenderer, .applied)
        } catch {
            return emitReport(.startOutputRenderer, AudioInputStreamCapture.operationResult(for: error))
        }
    }

    @discardableResult
    public func stop() -> AudioStreamOperationReport {
        guard isRunning else {
            return emitReport(.stopOutputRenderer, .ignored(.alreadyStopped))
        }
        do {
            try backend.stopRendering()
            isRunning = false
            return emitReport(.stopOutputRenderer, .applied)
        } catch {
            return emitReport(.stopOutputRenderer, AudioInputStreamCapture.operationResult(for: error))
        }
    }

    @discardableResult
    public func schedule(_ frame: AudioStreamFrame) -> AudioStreamOperationReport {
        guard frame.format == configuration.format else {
            return emitReport(
                .scheduleOutputFrame,
                .failed(.invalidFrame("frame format does not match output configuration"))
            )
        }
        do {
            try backend.schedule(frame)
            scheduledFrameCount += 1
            let report = emitReport(.scheduleOutputFrame, .applied)
            runtimeEventHandler?(.outputFrameScheduled(frame))
            return report
        } catch {
            return emitReport(.scheduleOutputFrame, AudioInputStreamCapture.operationResult(for: error))
        }
    }

    private func snapshot() -> AudioStreamSnapshot {
        AudioStreamSnapshot(
            direction: .output,
            isRunning: isRunning,
            format: configuration.format,
            processedFrameCount: scheduledFrameCount
        )
    }

    private func emitReport(
        _ operation: AudioStreamOperation,
        _ result: AudioStreamOperationResult
    ) -> AudioStreamOperationReport {
        let report = AudioStreamOperationReport(
            operation: operation,
            result: result,
            snapshot: snapshot()
        )
        runtimeEventHandler?(.operation(report))
        return report
    }
}

private extension AudioInputStreamCapture {
    static func operationResult(for error: Error) -> AudioStreamOperationResult {
        switch error as? AudioStreamError {
        case .unsupportedOnCurrentPlatform:
            .ignored(.unsupportedOnCurrentPlatform)
        case .invalidFrame(let message):
            .failed(.invalidFrame(message))
        case .engineOperationFailed(let message):
            .failed(.engineOperationFailed(message))
        case nil:
            .failed(.unexpected(String(describing: error)))
        }
    }
}

#if canImport(AVFAudio)
public final class SystemAudioInputStreamBackend: AudioInputStreamBackend {
    private let engine: AVAudioEngine
    private let bus: AVAudioNodeBus
    private let voiceProcessingManager: AudioInputVoiceProcessingManager
    private var nextSequenceNumber: UInt64 = 0

    public init(
        engine: AVAudioEngine = AVAudioEngine(),
        bus: AVAudioNodeBus = 0,
        voiceProcessingManager: AudioInputVoiceProcessingManager? = nil
    ) {
        self.engine = engine
        self.bus = bus
        self.voiceProcessingManager = voiceProcessingManager ?? AudioInputVoiceProcessingManager(
            backend: SystemAudioInputVoiceProcessingBackend(inputNode: engine.inputNode)
        )
    }

    public func startCapture(
        configuration: AudioInputStreamConfiguration,
        onFrame: @escaping (AudioStreamFrame) -> Void
    ) throws {
        try voiceProcessingManager.configure(configuration.voiceProcessing)
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: bus)
        inputNode.removeTap(onBus: bus)
        inputNode.installTap(
            onBus: bus,
            bufferSize: configuration.bufferFrameCount,
            format: inputFormat
        ) { [weak self] buffer, time in
            guard let self,
                  let frame = AudioStreamFrame(
                    buffer: buffer,
                    sequenceNumber: self.nextSequenceNumber,
                    targetFormat: configuration.format,
                    capturedAt: time.hostTime == 0 ? Date().timeIntervalSince1970 : AVAudioTime.seconds(forHostTime: time.hostTime)
                  )
            else { return }
            self.nextSequenceNumber += 1
            onFrame(frame)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: bus)
            throw AudioStreamError.engineOperationFailed(error.localizedDescription)
        }
    }

    public func stopCapture() throws {
        engine.inputNode.removeTap(onBus: bus)
        engine.stop()
    }
}

public final class SystemAudioOutputStreamBackend: AudioOutputStreamBackend {
    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private var isGraphConfigured = false

    public init(
        engine: AVAudioEngine = AVAudioEngine(),
        playerNode: AVAudioPlayerNode = AVAudioPlayerNode()
    ) {
        self.engine = engine
        self.playerNode = playerNode
    }

    public func startRendering(configuration: AudioOutputStreamConfiguration) throws {
        if !isGraphConfigured {
            if !engine.attachedNodes.contains(playerNode) {
                engine.attach(playerNode)
            }
            guard let format = AVAudioFormat(streamFormat: configuration.format) else {
                throw AudioStreamError.invalidFrame("failed to create output format")
            }
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            isGraphConfigured = true
        }
        engine.prepare()
        do {
            if !engine.isRunning {
                try engine.start()
            }
            if !playerNode.isPlaying {
                playerNode.play()
            }
        } catch {
            throw AudioStreamError.engineOperationFailed(error.localizedDescription)
        }
    }

    public func stopRendering() throws {
        playerNode.stop()
        engine.stop()
    }

    public func schedule(_ frame: AudioStreamFrame) throws {
        let buffer = try frame.makePCMBuffer()
        playerNode.scheduleBuffer(buffer, at: nil, options: [])
    }
}

private extension AVAudioFormat {
    convenience init?(streamFormat: AudioStreamFormat) {
        self.init(
            commonFormat: .pcmFormatFloat32,
            sampleRate: streamFormat.sampleRate,
            channels: AVAudioChannelCount(streamFormat.channelCount),
            interleaved: false
        )
    }
}

extension AudioStreamFrame {
    init?(
        buffer: AVAudioPCMBuffer,
        sequenceNumber: UInt64,
        targetFormat: AudioStreamFormat,
        capturedAt: TimeInterval
    ) {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            self.init(sequenceNumber: sequenceNumber, format: targetFormat, capturedAt: capturedAt, samples: [])
            return
        }

        let availableChannels = Int(buffer.format.channelCount)
        let channelCount = min(targetFormat.channelCount, max(1, availableChannels))
        var samples: [Float] = []
        samples.reserveCapacity(frameLength * targetFormat.channelCount)
        for frameIndex in 0..<frameLength {
            for channelIndex in 0..<targetFormat.channelCount {
                let sourceChannel = min(channelIndex, channelCount - 1)
                samples.append(channelData[sourceChannel][frameIndex])
            }
        }
        self.init(
            sequenceNumber: sequenceNumber,
            format: targetFormat,
            capturedAt: capturedAt,
            samples: samples
        )
    }

    func makePCMBuffer() throws -> AVAudioPCMBuffer {
        guard samples.count.isMultiple(of: format.channelCount) else {
            throw AudioStreamError.invalidFrame("sample count is not divisible by channel count")
        }
        guard let avFormat = AVAudioFormat(streamFormat: format),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: avFormat,
                frameCapacity: AVAudioFrameCount(samples.count / format.channelCount)
              ),
              let channelData = buffer.floatChannelData
        else {
            throw AudioStreamError.invalidFrame("failed to create PCM buffer")
        }

        let frameCount = samples.count / format.channelCount
        buffer.frameLength = AVAudioFrameCount(frameCount)
        for frameIndex in 0..<frameCount {
            for channelIndex in 0..<format.channelCount {
                channelData[channelIndex][frameIndex] = samples[frameIndex * format.channelCount + channelIndex]
            }
        }
        return buffer
    }
}
#endif
