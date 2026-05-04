import Foundation

public struct AudioCodecIdentifier: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String { rawValue }

    public static let pcm16 = AudioCodecIdentifier(rawValue: "pcm16")
    public static let opus = AudioCodecIdentifier(rawValue: "opus")
    public static let mpeg4AACELDv2 = AudioCodecIdentifier(rawValue: "mpeg4AACELDv2")
    public static let routeManaged = AudioCodecIdentifier(rawValue: "route-managed")
}

public enum AudioMediaOwnership: String, Codable, Equatable, Sendable {
    case appManagedPacketAudio
    case routeManagedMediaStream
}

public struct AudioFormatDescriptor: Codable, Equatable, Sendable {
    public var sampleRate: Double
    public var channelCount: Int

    public init(sampleRate: Double = 48_000, channelCount: Int = 1) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

public struct AudioCodecConfiguration: Codable, Equatable, Sendable {
    public var preferredCodecs: [AudioCodecIdentifier]

    public init(preferredCodecs: [AudioCodecIdentifier] = [.pcm16]) {
        self.preferredCodecs = preferredCodecs.isEmpty ? [.pcm16] : preferredCodecs
    }
}

public enum AudioCodecError: Error, Equatable, Sendable {
    case unsupportedCodec(AudioCodecIdentifier)
    case noMutuallySupportedCodec(preferred: [AudioCodecIdentifier], supported: [AudioCodecIdentifier])
}

public protocol AudioFrameCodec: Sendable {
    var identifier: AudioCodecIdentifier { get }

    func encode(_ frame: AudioFrame) throws -> EncodedAudioFrame
    func decode(_ frame: EncodedAudioFrame) throws -> AudioFrame
}

public struct AnyAudioFrameCodec: AudioFrameCodec {
    public let identifier: AudioCodecIdentifier
    private let encodeFrame: @Sendable (AudioFrame) throws -> EncodedAudioFrame
    private let decodeFrame: @Sendable (EncodedAudioFrame) throws -> AudioFrame

    public init(
        identifier: AudioCodecIdentifier,
        encode: @escaping @Sendable (AudioFrame) throws -> EncodedAudioFrame,
        decode: @escaping @Sendable (EncodedAudioFrame) throws -> AudioFrame
    ) {
        self.identifier = identifier
        self.encodeFrame = encode
        self.decodeFrame = decode
    }

    public func encode(_ frame: AudioFrame) throws -> EncodedAudioFrame {
        try encodeFrame(frame)
    }

    public func decode(_ frame: EncodedAudioFrame) throws -> AudioFrame {
        try decodeFrame(frame)
    }
}

public struct AudioCodecRegistry: Sendable {
    private var codecs: [AudioCodecIdentifier: any AudioFrameCodec]

    public init(codecs: [any AudioFrameCodec]) {
        var registeredCodecs: [AudioCodecIdentifier: any AudioFrameCodec] = [:]
        for codec in codecs {
            registeredCodecs[codec.identifier] = codec
        }
        self.codecs = registeredCodecs
    }

    public var supportedCodecs: [AudioCodecIdentifier] {
        codecs.keys.sorted { $0.rawValue < $1.rawValue }
    }

    public func codec(for identifier: AudioCodecIdentifier) -> (any AudioFrameCodec)? {
        codecs[identifier]
    }

    public func selectCodec(preferred: [AudioCodecIdentifier]) throws -> AudioCodecIdentifier {
        for identifier in preferred where codecs[identifier] != nil {
            return identifier
        }
        throw AudioCodecError.noMutuallySupportedCodec(preferred: preferred, supported: supportedCodecs)
    }

    public func encode(_ frame: AudioFrame, using identifier: AudioCodecIdentifier) throws -> EncodedAudioFrame {
        guard let codec = codec(for: identifier) else {
            throw AudioCodecError.unsupportedCodec(identifier)
        }
        return try codec.encode(frame)
    }

    public func decode(_ frame: EncodedAudioFrame) throws -> AudioFrame {
        guard let codec = codec(for: frame.codec) else {
            throw AudioCodecError.unsupportedCodec(frame.codec)
        }
        return try codec.decode(frame)
    }
}

public struct AudioFrame: Equatable, Sendable {
    public var sequenceNumber: UInt64
    public var format: AudioFormatDescriptor
    public var capturedAt: TimeInterval
    public var samples: [Float]

    public init(
        sequenceNumber: UInt64,
        format: AudioFormatDescriptor = AudioFormatDescriptor(),
        capturedAt: TimeInterval = Date().timeIntervalSince1970,
        samples: [Float]
    ) {
        self.sequenceNumber = sequenceNumber
        self.format = format
        self.capturedAt = capturedAt
        self.samples = samples
    }
}

public struct EncodedAudioFrame: Codable, Equatable, Sendable {
    public var sequenceNumber: UInt64
    public var codec: AudioCodecIdentifier
    public var format: AudioFormatDescriptor
    public var capturedAt: TimeInterval
    public var sampleCount: Int?
    public var payload: Data

    public init(
        sequenceNumber: UInt64,
        codec: AudioCodecIdentifier,
        format: AudioFormatDescriptor,
        capturedAt: TimeInterval,
        sampleCount: Int? = nil,
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

public struct ReceivedAudioFrame: Equatable, Sendable {
    public var peerID: PeerID
    public var frame: AudioFrame

    public init(peerID: PeerID, frame: AudioFrame) {
        self.peerID = peerID
        self.frame = frame
    }
}

public struct AudioLevel: Codable, Equatable, Sendable {
    public var rms: Float
    public var peak: Float

    public init(rms: Float, peak: Float) {
        self.rms = rms
        self.peak = peak
    }
}
