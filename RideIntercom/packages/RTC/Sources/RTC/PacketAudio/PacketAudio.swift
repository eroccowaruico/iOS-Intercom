import CryptoKit
import Foundation

public enum PCMAudioCodec {
    public enum CodecError: Error, Equatable {
        case invalidByteCount
    }

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
            let value = Int16(littleEndian: Int16(bitPattern: low | high))
            if value == Int16.min { return -1 }
            if value < 0 { return Float(value) / 32_768 }
            return Float(value) / Float(Int16.max)
        }
    }
}

public struct PCM16AudioCodec: AudioFrameCodec {
    public let identifier: AudioCodecIdentifier = .pcm16

    public init() {}

    public func encode(_ frame: AudioFrame) throws -> EncodedAudioFrame {
        EncodedAudioFrame(
            sequenceNumber: frame.sequenceNumber,
            codec: identifier,
            format: frame.format,
            capturedAt: frame.capturedAt,
            sampleCount: frame.samples.count,
            payload: PCMAudioCodec.encode(frame.samples)
        )
    }

    public func decode(_ frame: EncodedAudioFrame) throws -> AudioFrame {
        guard frame.codec == identifier else {
            throw AudioCodecError.unsupportedCodec(frame.codec)
        }
        return AudioFrame(
            sequenceNumber: frame.sequenceNumber,
            format: frame.format,
            capturedAt: frame.capturedAt,
            samples: try PCMAudioCodec.decode(frame.payload)
        )
    }
}

public extension AudioCodecRegistry {
    static var packetAudioDefault: AudioCodecRegistry {
        AudioCodecRegistry(codecs: [PCM16AudioCodec()])
    }
}

struct PacketAudioEnvelope: Codable, Equatable, Sendable {
    var sessionID: String
    var senderID: PeerID
    var streamID: UUID
    var frame: EncodedAudioFrame
}

struct PacketAudioSequencer: Sendable {
    private let sessionID: String
    private let senderID: PeerID
    private let streamID: UUID
    private let codecID: AudioCodecIdentifier
    private let codecRegistry: AudioCodecRegistry

    init(
        sessionID: String,
        senderID: PeerID,
        codecID: AudioCodecIdentifier,
        codecRegistry: AudioCodecRegistry,
        streamID: UUID = UUID()
    ) {
        self.sessionID = sessionID
        self.senderID = senderID
        self.codecID = codecID
        self.codecRegistry = codecRegistry
        self.streamID = streamID
    }

    func makeEnvelope(from frame: AudioFrame) throws -> PacketAudioEnvelope {
        PacketAudioEnvelope(
            sessionID: sessionID,
            senderID: senderID,
            streamID: streamID,
            frame: try codecRegistry.encode(frame, using: codecID)
        )
    }
}

struct PacketAudioReceiveFilter: Sendable {
    private let sessionID: String
    private let codecRegistry: AudioCodecRegistry
    private var seenPackets: Set<PacketID> = []

    init(sessionID: String, codecRegistry: AudioCodecRegistry) {
        self.sessionID = sessionID
        self.codecRegistry = codecRegistry
    }

    mutating func accept(_ envelope: PacketAudioEnvelope, from peerID: PeerID) throws -> ReceivedAudioFrame? {
        guard envelope.sessionID == sessionID else { return nil }
        let packetID = PacketID(streamID: envelope.streamID, sequenceNumber: envelope.frame.sequenceNumber)
        guard !seenPackets.contains(packetID) else { return nil }
        seenPackets.insert(packetID)
        return ReceivedAudioFrame(
            peerID: peerID,
            frame: try codecRegistry.decode(envelope.frame)
        )
    }

    private struct PacketID: Hashable {
        var streamID: UUID
        var sequenceNumber: UInt64
    }
}

struct RouteHandshakeMessage: Codable, Equatable, Sendable {
    var groupHash: String
    var senderID: PeerID
    var nonce: String
    var mac: String

    static func make(credential: RTCCredential, senderID: PeerID, nonce: String = UUID().uuidString) -> RouteHandshakeMessage {
        RouteHandshakeMessage(
            groupHash: credential.groupHash,
            senderID: senderID,
            nonce: nonce,
            mac: mac(groupHash: credential.groupHash, senderID: senderID, nonce: nonce, secret: credential.sharedSecret)
        )
    }

    func verify(credential: RTCCredential) -> Bool {
        groupHash == credential.groupHash
            && mac == Self.mac(groupHash: groupHash, senderID: senderID, nonce: nonce, secret: credential.sharedSecret)
    }

    private static func mac(groupHash: String, senderID: PeerID, nonce: String, secret: Data) -> String {
        let key = SymmetricKey(data: secret)
        let message = [groupHash, senderID.rawValue, nonce].joined(separator: "|")
        return HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum RouteControlPayload: Codable, Equatable, Sendable {
    case keepalive
    case handshake(RouteHandshakeMessage)
}

enum MultipeerWireMessage: Codable, Equatable, Sendable {
    case control(RouteControlPayload)
    case applicationData(ApplicationDataMessage)
    case packetAudio(PacketAudioEnvelope)
}

enum TransportSendMode: Equatable, Sendable {
    case reliable
    case unreliable
}

struct TransportPayload: Equatable, Sendable {
    var data: Data
    var mode: TransportSendMode
}

enum MultipeerPayloadBuilder {
    static func makeControlPayload(_ payload: RouteControlPayload) throws -> TransportPayload {
        let mode: TransportSendMode
        switch payload {
        case .keepalive:
            mode = .unreliable
        case .handshake:
            mode = .reliable
        }
        return TransportPayload(data: try encode(.control(payload)), mode: mode)
    }

    static func makeApplicationDataPayload(_ message: ApplicationDataMessage) throws -> TransportPayload {
        let mode: TransportSendMode = message.delivery == .reliable ? .reliable : .unreliable
        return TransportPayload(data: try encode(.applicationData(message)), mode: mode)
    }

    static func makePacketAudioPayload(_ envelope: PacketAudioEnvelope, credential: RTCCredential?) throws -> TransportPayload {
        let messageData = try encode(.packetAudio(envelope))
        let data: Data
        if let credential {
            data = try PacketCrypto.seal(messageData, credential: credential)
        } else {
            data = messageData
        }
        return TransportPayload(data: data, mode: .unreliable)
    }

    static func decode(_ data: Data, credential: RTCCredential?) throws -> MultipeerWireMessage {
        if let decoded = try? JSONDecoder().decode(MultipeerWireMessage.self, from: data) {
            return decoded
        }
        guard let credential else {
            throw DecodeError.unknownPayload
        }
        return try JSONDecoder().decode(MultipeerWireMessage.self, from: PacketCrypto.open(data, credential: credential))
    }

    private static func encode(_ message: MultipeerWireMessage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(message)
    }

    enum DecodeError: Error, Equatable {
        case unknownPayload
    }
}

enum PacketCrypto {
    static func seal(_ data: Data, credential: RTCCredential) throws -> Data {
        let box = try AES.GCM.seal(data, using: SymmetricKey(data: credential.sharedSecret))
        guard let combined = box.combined else { throw CryptoError.missingCombinedRepresentation }
        return combined
    }

    static func open(_ data: Data, credential: RTCCredential) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: SymmetricKey(data: credential.sharedSecret))
    }

    enum CryptoError: Error, Equatable {
        case missingCombinedRepresentation
    }
}
