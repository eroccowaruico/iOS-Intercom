import AudioToolbox
@preconcurrency import AVFAudio
import Foundation

public enum CodecError: Error, Equatable, Sendable {
    case invalidSampleCount(sampleCount: Int, channelCount: Int)
    case invalidByteCount
    case invalidFormat(CodecAudioFormat)
    case unsupportedCodec(CodecIdentifier)
    case encoderUnavailable(CodecIdentifier)
    case decoderUnavailable(CodecIdentifier)
    case audioFormatCreationFailed(CodecIdentifier)
    case conversionFailed(CodecIdentifier, String)
    case malformedPayload(CodecIdentifier)
}

public enum CodecIdentifier: String, Codable, CaseIterable, Equatable, Sendable {
    case pcm16
    case mpeg4AACELDv2
    case opus

    public var displayName: String {
        switch self {
        case .pcm16:
            "PCM 16-bit"
        case .mpeg4AACELDv2:
            "MPEG-4 AAC-ELD v2"
        case .opus:
            "Opus"
        }
    }

    public var audioFormatID: AudioFormatID {
        switch self {
        case .pcm16:
            kAudioFormatLinearPCM
        case .mpeg4AACELDv2:
            kAudioFormatMPEG4AAC_ELD_V2
        case .opus:
            kAudioFormatOpus
        }
    }
}

public struct CodecAudioFormat: Codable, Equatable, Sendable {
    public static let defaultSampleRate: Double = 48_000
    public static let allowedSampleRateRange: ClosedRange<Double> = 8_000...96_000
    public static let allowedChannelCountRange: ClosedRange<Int> = 1...2

    public var sampleRate: Double
    public var channelCount: Int

    public init(sampleRate: Double = Self.defaultSampleRate, channelCount: Int = 1) {
        self.sampleRate = Self.clamp(sampleRate, Self.allowedSampleRateRange)
        self.channelCount = Self.clamp(channelCount, Self.allowedChannelCountRange)
    }

    func avAudioFrameCount(forSampleCount sampleCount: Int) throws -> AVAudioFrameCount {
        guard sampleCount.isMultiple(of: channelCount) else {
            throw CodecError.invalidSampleCount(sampleCount: sampleCount, channelCount: channelCount)
        }
        return AVAudioFrameCount(sampleCount / channelCount)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

public struct AACELDv2Options: Codable, Equatable, Sendable {
    public static let allowedBitRateRange: ClosedRange<Int> = 12_000...128_000

    public var bitRate: Int

    public init(bitRate: Int = 24_000) {
        self.bitRate = Self.clamp(bitRate, Self.allowedBitRateRange)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

public struct OpusOptions: Codable, Equatable, Sendable {
    public static let allowedBitRateRange: ClosedRange<Int> = 6_000...128_000

    public var bitRate: Int

    public init(bitRate: Int = 32_000) {
        self.bitRate = Self.clamp(bitRate, Self.allowedBitRateRange)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

public struct CodecEncodingConfiguration: Codable, Equatable, Sendable {
    public var codec: CodecIdentifier
    public var format: CodecAudioFormat
    public var aacELDv2Options: AACELDv2Options
    public var opusOptions: OpusOptions

    public init(
        codec: CodecIdentifier = .pcm16,
        format: CodecAudioFormat = CodecAudioFormat(),
        aacELDv2Options: AACELDv2Options = AACELDv2Options(),
        opusOptions: OpusOptions = OpusOptions()
    ) {
        self.codec = codec
        self.format = format
        self.aacELDv2Options = aacELDv2Options
        self.opusOptions = opusOptions
    }

    var activeBitRate: Int? {
        switch codec {
        case .pcm16:
            nil
        case .mpeg4AACELDv2:
            aacELDv2Options.bitRate
        case .opus:
            opusOptions.bitRate
        }
    }
}

public struct PCMCodecFrame: Equatable, Sendable {
    public var sequenceNumber: UInt64
    public var format: CodecAudioFormat
    public var capturedAt: TimeInterval
    public var samples: [Float]

    public init(
        sequenceNumber: UInt64,
        format: CodecAudioFormat = CodecAudioFormat(),
        capturedAt: TimeInterval = Date().timeIntervalSince1970,
        samples: [Float]
    ) {
        self.sequenceNumber = sequenceNumber
        self.format = format
        self.capturedAt = capturedAt
        self.samples = samples
    }
}

public struct EncodedCodecFrame: Codable, Equatable, Sendable {
    public var sequenceNumber: UInt64
    public var codec: CodecIdentifier
    public var format: CodecAudioFormat
    public var capturedAt: TimeInterval
    public var sampleCount: Int
    public var payload: Data

    public init(
        sequenceNumber: UInt64,
        codec: CodecIdentifier,
        format: CodecAudioFormat,
        capturedAt: TimeInterval,
        sampleCount: Int,
        payload: Data
    ) {
        self.sequenceNumber = sequenceNumber
        self.codec = codec
        self.format = format
        self.capturedAt = capturedAt
        self.sampleCount = sampleCount
        self.payload = payload
    }
}

public enum CodecSupport {
    public static func isEncodingAvailable(for configuration: CodecEncodingConfiguration) -> Bool {
        switch configuration.codec {
        case .pcm16:
            return true
        case .mpeg4AACELDv2, .opus:
            guard let pcmFormat = AudioConverterBridge.makePCMFormat(configuration.format),
                  let compressedFormat = AudioConverterBridge.makeCompressedFormat(
                    codec: configuration.codec,
                    format: configuration.format,
                    bitRate: configuration.activeBitRate
                  ) else {
                return false
            }
            return AVAudioConverter(from: pcmFormat, to: compressedFormat) != nil
        }
    }

    public static func isDecodingAvailable(for codec: CodecIdentifier, format: CodecAudioFormat = CodecAudioFormat()) -> Bool {
        switch codec {
        case .pcm16:
            return true
        case .mpeg4AACELDv2, .opus:
            guard let pcmFormat = AudioConverterBridge.makePCMFormat(format),
                  let compressedFormat = AudioConverterBridge.makeCompressedFormat(codec: codec, format: format, bitRate: nil) else {
                return false
            }
            return AVAudioConverter(from: compressedFormat, to: pcmFormat) != nil
        }
    }
}

public final class AudioCodec {
    private let decoder = CodecDecoder()
    private let encoder: CodecEncoder

    public var configuration: CodecEncodingConfiguration {
        encoder.configuration
    }

    public init(configuration: CodecEncodingConfiguration = CodecEncodingConfiguration()) {
        self.encoder = CodecEncoder(configuration: configuration)
    }

    public func apply(_ configuration: CodecEncodingConfiguration) {
        encoder.apply(configuration)
    }

    public func encode(_ frame: PCMCodecFrame) throws -> EncodedCodecFrame {
        try encoder.encode(frame)
    }

    public func encode(
        sequenceNumber: UInt64,
        samples: [Float],
        capturedAt: TimeInterval = Date().timeIntervalSince1970
    ) throws -> EncodedCodecFrame {
        try encoder.encode(sequenceNumber: sequenceNumber, samples: samples, capturedAt: capturedAt)
    }

    public func decode(_ frame: EncodedCodecFrame) throws -> PCMCodecFrame {
        try decoder.decode(frame)
    }
}

public final class CodecEncoder {
    public private(set) var configuration: CodecEncodingConfiguration

    public init(configuration: CodecEncodingConfiguration = CodecEncodingConfiguration()) {
        self.configuration = configuration
    }

    public func apply(_ configuration: CodecEncodingConfiguration) {
        self.configuration = configuration
    }

    public func encode(
        sequenceNumber: UInt64,
        samples: [Float],
        capturedAt: TimeInterval = Date().timeIntervalSince1970
    ) throws -> EncodedCodecFrame {
        try encode(PCMCodecFrame(sequenceNumber: sequenceNumber, format: configuration.format, capturedAt: capturedAt, samples: samples))
    }

    public func encode(_ frame: PCMCodecFrame) throws -> EncodedCodecFrame {
        let payload: Data
        switch configuration.codec {
        case .pcm16:
            payload = PCM16Codec.encode(frame.samples)
        case .mpeg4AACELDv2, .opus:
            payload = try AudioConverterBridge.encode(
                samples: frame.samples,
                codec: configuration.codec,
                format: frame.format,
                bitRate: configuration.activeBitRate
            )
        }

        return EncodedCodecFrame(
            sequenceNumber: frame.sequenceNumber,
            codec: configuration.codec,
            format: frame.format,
            capturedAt: frame.capturedAt,
            sampleCount: frame.samples.count,
            payload: payload
        )
    }
}

public final class CodecDecoder {
    public init() {}

    public func decode(_ frame: EncodedCodecFrame) throws -> PCMCodecFrame {
        let samples: [Float]
        switch frame.codec {
        case .pcm16:
            samples = try PCM16Codec.decode(frame.payload)
        case .mpeg4AACELDv2, .opus:
            samples = try AudioConverterBridge.decode(payload: frame.payload, codec: frame.codec, format: frame.format)
        }

        return PCMCodecFrame(
            sequenceNumber: frame.sequenceNumber,
            format: frame.format,
            capturedAt: frame.capturedAt,
            samples: samples
        )
    }
}

public enum PCM16Codec {
    public static func encode(_ samples: [Float]) -> Data {
        var data = Data()
        data.reserveCapacity(samples.count * MemoryLayout<Int16>.size)

        for sample in samples {
            let clamped = min(1, max(-1, sample))
            let scale: Float = clamped < 0 ? 32_768 : 32_767
            let rounded = Int((clamped * scale).rounded(.toNearestOrAwayFromZero))
            let bounded = min(Int(Int16.max), max(Int(Int16.min), rounded))
            let encoded = Int16(bounded).littleEndian
            data.append(UInt8(truncatingIfNeeded: encoded))
            data.append(UInt8(truncatingIfNeeded: encoded >> 8))
        }

        return data
    }

    public static func decode(_ data: Data) throws -> [Float] {
        guard data.count.isMultiple(of: MemoryLayout<Int16>.size) else {
            throw CodecError.invalidByteCount
        }

        return stride(from: 0, to: data.count, by: MemoryLayout<Int16>.size).map { offset in
            let low = UInt16(data[offset])
            let high = UInt16(data[offset + 1]) << 8
            let rawValue = Int16(littleEndian: Int16(bitPattern: low | high))
            if rawValue == Int16.min {
                return -1
            }
            if rawValue < 0 {
                return Float(rawValue) / 32_768
            }
            return Float(rawValue) / Float(Int16.max)
        }
    }
}

private enum AudioConverterBridge {
    static func encode(samples: [Float], codec: CodecIdentifier, format: CodecAudioFormat, bitRate: Int?) throws -> Data {
        guard codec != .pcm16 else { return PCM16Codec.encode(samples) }
        guard !samples.isEmpty else {
            return try CompressedPayloadEnvelope.empty(codec: codec).encoded()
        }

        let frameCount = try format.avAudioFrameCount(forSampleCount: samples.count)
        guard let pcmFormat = makePCMFormat(format) else {
            throw CodecError.invalidFormat(format)
        }
        guard let compressedFormat = makeCompressedFormat(codec: codec, format: format, bitRate: bitRate) else {
            throw CodecError.audioFormatCreationFailed(codec)
        }
        guard let converter = AVAudioConverter(from: pcmFormat, to: compressedFormat) else {
            throw CodecError.encoderUnavailable(codec)
        }

        let inputBuffer = try makePCMBuffer(samples: samples, format: format, avFormat: pcmFormat, frameCount: frameCount)
        let packetCapacity = max(1, AVAudioPacketCount(frameCount))
        let outputBuffer = AVAudioCompressedBuffer(
            format: compressedFormat,
            packetCapacity: packetCapacity,
            maximumPacketSize: max(1, converter.maximumOutputPacketSize)
        )

        let inputProvider = OneShotAudioBufferProvider(inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            inputProvider.provide(inputStatus)
        }

        guard status != .error else {
            throw CodecError.conversionFailed(codec, conversionError?.localizedDescription ?? "Unknown AudioConverter encode error")
        }

        return try CompressedPayloadEnvelope(
            codec: codec,
            sourceSampleCount: samples.count,
            sourceFrameCount: UInt32(frameCount),
            maximumPacketSize: max(1, converter.maximumOutputPacketSize),
            packetCount: outputBuffer.packetCount,
            packetDescriptions: packetDescriptions(from: outputBuffer),
            data: Data(bytes: outputBuffer.data, count: Int(outputBuffer.byteLength))
        ).encoded()
    }

    static func decode(payload: Data, codec: CodecIdentifier, format: CodecAudioFormat) throws -> [Float] {
        guard codec != .pcm16 else { return try PCM16Codec.decode(payload) }
        guard !payload.isEmpty else { return [] }

        let envelope = try CompressedPayloadEnvelope.decode(payload, expectedCodec: codec)
        guard !envelope.data.isEmpty else { return [] }
        guard let pcmFormat = makePCMFormat(format) else {
            throw CodecError.invalidFormat(format)
        }
        guard let compressedFormat = makeCompressedFormat(codec: codec, format: format, bitRate: nil) else {
            throw CodecError.audioFormatCreationFailed(codec)
        }
        guard let converter = AVAudioConverter(from: compressedFormat, to: pcmFormat) else {
            throw CodecError.decoderUnavailable(codec)
        }

        let inputBuffer = AVAudioCompressedBuffer(
            format: compressedFormat,
            packetCapacity: max(1, envelope.packetCount),
            maximumPacketSize: max(1, envelope.maximumPacketSize)
        )
        inputBuffer.byteLength = UInt32(envelope.data.count)
        inputBuffer.packetCount = envelope.packetCount
        envelope.data.withUnsafeBytes { source in
            if let baseAddress = source.baseAddress {
                inputBuffer.data.copyMemory(from: baseAddress, byteCount: envelope.data.count)
            }
        }
        if let destinationDescriptions = inputBuffer.packetDescriptions {
            for (index, description) in envelope.packetDescriptions.enumerated() {
                destinationDescriptions[index] = description.audioStreamPacketDescription
            }
        }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: pcmFormat,
            frameCapacity: max(1, AVAudioFrameCount(envelope.sourceFrameCount))
        ) else {
            throw CodecError.audioFormatCreationFailed(codec)
        }

        let inputProvider = OneShotAudioBufferProvider(inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            inputProvider.provide(inputStatus)
        }

        guard status != .error else {
            throw CodecError.conversionFailed(codec, conversionError?.localizedDescription ?? "Unknown AudioConverter decode error")
        }

        return try samples(from: outputBuffer, format: format, sampleLimit: envelope.sourceSampleCount)
    }

    static func makePCMFormat(_ format: CodecAudioFormat) -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: AVAudioChannelCount(format.channelCount),
            interleaved: false
        )
    }

    static func makeCompressedFormat(codec: CodecIdentifier, format: CodecAudioFormat, bitRate: Int?) -> AVAudioFormat? {
        guard codec != .pcm16 else { return makePCMFormat(format) }

        var settings: [String: Any] = [
            AVFormatIDKey: codec.audioFormatID,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
        ]

        if let bitRate {
            settings[AVEncoderBitRateKey] = bitRate
        }

        return AVAudioFormat(settings: settings)
    }

    private static func makePCMBuffer(
        samples: [Float],
        format: CodecAudioFormat,
        avFormat: AVAudioFormat,
        frameCount: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: avFormat, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            throw CodecError.audioFormatCreationFailed(.pcm16)
        }

        buffer.frameLength = frameCount
        for frameIndex in 0..<Int(frameCount) {
            for channelIndex in 0..<format.channelCount {
                channels[channelIndex][frameIndex] = samples[frameIndex * format.channelCount + channelIndex]
            }
        }

        return buffer
    }

    private static func samples(from buffer: AVAudioPCMBuffer, format: CodecAudioFormat, sampleLimit: Int) throws -> [Float] {
        guard let channels = buffer.floatChannelData else {
            throw CodecError.audioFormatCreationFailed(.pcm16)
        }

        let frameLength = Int(buffer.frameLength)
        var samples: [Float] = []
        samples.reserveCapacity(frameLength * format.channelCount)
        for frameIndex in 0..<frameLength {
            for channelIndex in 0..<format.channelCount {
                samples.append(channels[channelIndex][frameIndex])
            }
        }

        if samples.count > sampleLimit {
            samples.removeLast(samples.count - sampleLimit)
        }
        return samples
    }

    private static func packetDescriptions(from buffer: AVAudioCompressedBuffer) -> [CompressedPayloadEnvelope.PacketDescription] {
        guard let packetDescriptions = buffer.packetDescriptions else { return [] }
        return (0..<Int(buffer.packetCount)).map { index in
            CompressedPayloadEnvelope.PacketDescription(packetDescriptions[index])
        }
    }
}

private final class OneShotAudioBufferProvider: @unchecked Sendable {
    private let buffer: AVAudioBuffer
    private var didProvideInput = false

    init(_ buffer: AVAudioBuffer) {
        self.buffer = buffer
    }

    func provide(_ inputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if didProvideInput {
            inputStatus.pointee = .endOfStream
            return nil
        }

        didProvideInput = true
        inputStatus.pointee = .haveData
        return buffer
    }
}

private struct CompressedPayloadEnvelope: Codable, Equatable, Sendable {
    struct PacketDescription: Codable, Equatable, Sendable {
        var startOffset: Int64
        var variableFramesInPacket: UInt32
        var dataByteSize: UInt32

        init(_ description: AudioStreamPacketDescription) {
            self.startOffset = description.mStartOffset
            self.variableFramesInPacket = description.mVariableFramesInPacket
            self.dataByteSize = description.mDataByteSize
        }

        var audioStreamPacketDescription: AudioStreamPacketDescription {
            AudioStreamPacketDescription(
                mStartOffset: startOffset,
                mVariableFramesInPacket: variableFramesInPacket,
                mDataByteSize: dataByteSize
            )
        }
    }

    var codec: CodecIdentifier
    var sourceSampleCount: Int
    var sourceFrameCount: UInt32
    var maximumPacketSize: Int
    var packetCount: UInt32
    var packetDescriptions: [PacketDescription]
    var data: Data

    static func empty(codec: CodecIdentifier) -> CompressedPayloadEnvelope {
        CompressedPayloadEnvelope(
            codec: codec,
            sourceSampleCount: 0,
            sourceFrameCount: 0,
            maximumPacketSize: 1,
            packetCount: 0,
            packetDescriptions: [],
            data: Data()
        )
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data, expectedCodec: CodecIdentifier) throws -> CompressedPayloadEnvelope {
        do {
            let envelope = try JSONDecoder().decode(CompressedPayloadEnvelope.self, from: data)
            guard envelope.codec == expectedCodec else {
                throw CodecError.malformedPayload(expectedCodec)
            }
            guard envelope.packetDescriptions.isEmpty || envelope.packetDescriptions.count == Int(envelope.packetCount) else {
                throw CodecError.malformedPayload(expectedCodec)
            }
            return envelope
        } catch let error as CodecError {
            throw error
        } catch {
            throw CodecError.malformedPayload(expectedCodec)
        }
    }
}
