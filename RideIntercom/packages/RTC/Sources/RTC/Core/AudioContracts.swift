import Foundation

public enum AudioCodecIdentifier: String, Codable, Equatable, Sendable {
    case pcm16
    case opus
    case heAACv2
    case routeManaged
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
    public var payload: Data

    public init(
        sequenceNumber: UInt64,
        codec: AudioCodecIdentifier,
        format: AudioFormatDescriptor,
        capturedAt: TimeInterval,
        payload: Data
    ) {
        self.sequenceNumber = sequenceNumber
        self.codec = codec
        self.format = format
        self.capturedAt = capturedAt
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
