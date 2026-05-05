import CryptoKit
import AVFoundation
import Codec
import Foundation
import Observation
import OSLog
import RTC
import SessionManager
import VADGate

enum OutboundAudioPacket: Equatable {
    case voice(frameID: Int, samples: [Float] = [])
    case keepalive
}

typealias AudioCodecIdentifier = RTC.AudioCodecIdentifier

extension RTC.AudioCodecIdentifier {
    static let heAACv2 = RTC.AudioCodecIdentifier.mpeg4AACELDv2
}

extension RTC.AudioFormatDescriptor {
    static let intercomPacketAudio = RTC.AudioFormatDescriptor(sampleRate: 16_000, channelCount: 1)

    init(codecFormat: Codec.CodecAudioFormat) {
        self.init(sampleRate: codecFormat.sampleRate, channelCount: codecFormat.channelCount)
    }
}

private extension Codec.CodecAudioFormat {
    init(rtcFormat: RTC.AudioFormatDescriptor) {
        self.init(sampleRate: rtcFormat.sampleRate, channelCount: rtcFormat.channelCount)
    }
}

private extension Codec.CodecIdentifier {
    var rtcIdentifier: RTC.AudioCodecIdentifier {
        RTC.AudioCodecIdentifier(rawValue: rawValue)
    }
}

private struct PackageAudioFrameCodec: RTC.AudioFrameCodec {
    let identifier: RTC.AudioCodecIdentifier
    private let codecIdentifier: Codec.CodecIdentifier
    private let aacELDv2Options: Codec.AACELDv2Options
    private let opusOptions: Codec.OpusOptions

    init(
        codecIdentifier: Codec.CodecIdentifier,
        aacELDv2Options: Codec.AACELDv2Options = Codec.AACELDv2Options(),
        opusOptions: Codec.OpusOptions = Codec.OpusOptions()
    ) {
        self.identifier = codecIdentifier.rtcIdentifier
        self.codecIdentifier = codecIdentifier
        self.aacELDv2Options = aacELDv2Options
        self.opusOptions = opusOptions
    }

    func encode(_ frame: RTC.AudioFrame) throws -> RTC.EncodedAudioFrame {
        let codecFormat = Codec.CodecAudioFormat(rtcFormat: frame.format)
        let configuration = Codec.CodecEncodingConfiguration(
            codec: codecIdentifier,
            format: codecFormat,
            aacELDv2Options: aacELDv2Options,
            opusOptions: opusOptions
        )
        let encoded = try Codec.CodecEncoder(configuration: configuration).encode(Codec.PCMCodecFrame(
            sequenceNumber: frame.sequenceNumber,
            format: codecFormat,
            capturedAt: frame.capturedAt,
            samples: frame.samples
        ))
        return RTC.EncodedAudioFrame(
            sequenceNumber: encoded.sequenceNumber,
            codec: encoded.codec.rtcIdentifier,
            format: RTC.AudioFormatDescriptor(codecFormat: encoded.format),
            capturedAt: encoded.capturedAt,
            sampleCount: encoded.sampleCount,
            payload: encoded.payload
        )
    }

    func decode(_ frame: RTC.EncodedAudioFrame) throws -> RTC.AudioFrame {
        guard frame.codec == identifier else {
            throw RTC.AudioCodecError.unsupportedCodec(frame.codec)
        }
        let codecFormat = Codec.CodecAudioFormat(rtcFormat: frame.format)
        let decoded = try Codec.CodecDecoder().decode(Codec.EncodedCodecFrame(
            sequenceNumber: frame.sequenceNumber,
            codec: codecIdentifier,
            format: codecFormat,
            capturedAt: frame.capturedAt,
            sampleCount: frame.sampleCount ?? 0,
            payload: frame.payload
        ))
        return RTC.AudioFrame(
            sequenceNumber: decoded.sequenceNumber,
            format: RTC.AudioFormatDescriptor(codecFormat: decoded.format),
            capturedAt: decoded.capturedAt,
            samples: decoded.samples
        )
    }
}

enum AppAudioCodecBridge {
    static func makeRTCCodecRegistry(format: RTC.AudioFormatDescriptor) -> RTC.AudioCodecRegistry {
        var codecs: [any RTC.AudioFrameCodec] = [RTC.PCM16AudioCodec()]
        for codecIdentifier in [Codec.CodecIdentifier.mpeg4AACELDv2, .opus]
        where isAvailable(codecIdentifier, format: format) {
            codecs.append(PackageAudioFrameCodec(codecIdentifier: codecIdentifier))
        }
        return RTC.AudioCodecRegistry(codecs: codecs)
    }

    static func preferredRTCCodecs(
        _ preferred: RTC.AudioCodecIdentifier,
        format: RTC.AudioFormatDescriptor
    ) -> [RTC.AudioCodecIdentifier] {
        let resolved = resolvedPreferredCodec(preferred, format: format)
        return resolved == .pcm16 ? [.pcm16] : [resolved, .pcm16]
    }

    static func resolvedPreferredCodec(
        _ preferred: RTC.AudioCodecIdentifier,
        format: RTC.AudioFormatDescriptor
    ) -> RTC.AudioCodecIdentifier {
        guard let codecIdentifier = Codec.CodecIdentifier(rawValue: preferred.rawValue),
              isAvailable(codecIdentifier, format: format) else {
            return .pcm16
        }
        return codecIdentifier.rtcIdentifier
    }

    private static func isAvailable(_ codecIdentifier: Codec.CodecIdentifier, format: RTC.AudioFormatDescriptor) -> Bool {
        let codecFormat = Codec.CodecAudioFormat(rtcFormat: format)
        let configuration = Codec.CodecEncodingConfiguration(codec: codecIdentifier, format: codecFormat)
        return Codec.CodecSupport.isEncodingAvailable(for: configuration)
            && Codec.CodecSupport.isDecodingAvailable(for: codecIdentifier, format: codecFormat)
    }
}

enum HEAACv2Quality: String, CaseIterable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var bitRate: Int {
        switch self {
        case .low:
            16_000
        case .medium:
            24_000
        case .high:
            40_000
        }
    }
}

struct EncodedVoicePacket: Codable, Equatable {
    let frameID: Int
    let codec: AudioCodecIdentifier
    let payload: Data

    nonisolated static func make(
        frameID: Int,
        samples: [Float]
    ) throws -> EncodedVoicePacket {
        try make(frameID: frameID, samples: samples, codec: .pcm16)
    }

    func decodeSamples() throws -> [Float] {
        try decodeSamples(using: PCMAudioEncoding())
    }

    nonisolated static func make(
        frameID: Int,
        samples: [Float],
        codec: AudioCodecIdentifier
    ) throws -> EncodedVoicePacket {
        _ = codec
        return try make(frameID: frameID, samples: samples, encoder: PCMAudioEncoding())
    }

    nonisolated static func make(
        frameID: Int,
        samples: [Float],
        encoder: any AudioEncoding
    ) throws -> EncodedVoicePacket {
        EncodedVoicePacket(
            frameID: frameID,
            codec: encoder.codec,
            payload: try encoder.encode(samples)
        )
    }

    func decodeSamples(using encoder: any AudioEncoding) throws -> [Float] {
        try encoder.decode(payload)
    }
}



struct AudioTransmitMetadata: Codable, Equatable {
    let requestedCodec: AudioCodecIdentifier
    let mediaCodec: AudioCodecIdentifier
}

enum RemoteMemberAudioStateService {
    static func applyReceivedVoice(
        to group: IntercomGroup,
        peerID: String,
        voiceLevel: Float,
        peakWindows: inout [String: VoicePeakWindow]
    ) -> IntercomGroup {
        var updated = group
        guard let memberIndex = updated.members.firstIndex(where: { $0.id == peerID }) else {
            return updated
        }

        let clampedLevel = min(1, max(0, voiceLevel))
        updated.members[memberIndex].isTalking = true
        updated.members[memberIndex].voiceLevel = clampedLevel
        updated.members[memberIndex].voicePeakLevel = peakWindows[peerID, default: VoicePeakWindow()].record(clampedLevel)
        updated.members[memberIndex].receivedAudioPacketCount += 1
        updated.members[memberIndex].queuedAudioFrameCount += 1
        return updated
    }

    static func applyPlayedFrames(_ frames: [JitterBufferedAudioFrame], to group: IntercomGroup) -> IntercomGroup {
        guard !frames.isEmpty else { return group }

        let playedByPeer = Dictionary(grouping: frames, by: \.peerID).mapValues(\.count)
        var updated = group
        updated.members = group.members.map { member in
            guard let playedCount = playedByPeer[member.id] else { return member }

            var member = member
            member.playedAudioFrameCount += playedCount
            member.queuedAudioFrameCount = 0
            return member
        }
        return updated
    }
}

enum RemoteAudioPacketAcceptanceService {
    static func acceptedReceiveTimestamp(
        peerID: String,
        authenticatedPeerIDs: [String],
        packetSentAt: TimeInterval,
        now: TimeInterval
    ) -> TimeInterval? {
        guard authenticatedPeerIDs.isEmpty || authenticatedPeerIDs.contains(peerID) else {
            return nil
        }

        return packetSentAt < 1_000_000 ? packetSentAt : now
    }
}

enum RemoteAudioPipelineService {
    struct IngressResult: Equatable {
        let receivedVoicePacketCountIncrement: Int
        let lastReceivedAudioAt: TimeInterval
        let jitterQueuedFrameCount: Int
    }

    struct DrainResult: Equatable {
        let readyFrames: [JitterBufferedAudioFrame]
        let droppedAudioPacketCount: Int
        let jitterQueuedFrameCount: Int
    }

    static func processReceivedPacket(
        _ packet: ReceivedAudioPacket,
        isAuthorized: Bool,
        receivedAt: TimeInterval,
        jitterBuffer: inout JitterBuffer
    ) -> IngressResult? {
        guard isAuthorized else { return nil }
        jitterBuffer.enqueue(packet, receivedAt: receivedAt)
        let increment: Int
        if case .voice = packet.packet {
            increment = 1
        } else {
            increment = 0
        }

        return IngressResult(
            receivedVoicePacketCountIncrement: increment,
            lastReceivedAudioAt: receivedAt,
            jitterQueuedFrameCount: jitterBuffer.queuedFrameCount
        )
    }

    static func drainReadyAudioFrames(now: TimeInterval, jitterBuffer: inout JitterBuffer) -> DrainResult {
        let readyFrames = jitterBuffer.drainReadyFrames(now: now)
        return DrainResult(
            readyFrames: readyFrames,
            droppedAudioPacketCount: jitterBuffer.droppedFrameCount,
            jitterQueuedFrameCount: jitterBuffer.queuedFrameCount
        )
    }
}

struct AudioPacketEnvelope: Codable, Equatable {
    enum PacketKind: String, Codable {
        case voice
    }

    let groupID: UUID
    let streamID: UUID
    let sequenceNumber: Int
    let sentAt: TimeInterval
    let kind: PacketKind
    let frameID: Int?
    let samples: [Float]
    let encodedVoice: EncodedVoicePacket?

    nonisolated init(
        groupID: UUID,
        streamID: UUID,
        sequenceNumber: Int,
        sentAt: TimeInterval,
        kind: PacketKind,
        frameID: Int?,
        samples: [Float] = [],
        encodedVoice: EncodedVoicePacket? = nil
    ) {
        self.groupID = groupID
        self.streamID = streamID
        self.sequenceNumber = sequenceNumber
        self.sentAt = sentAt
        self.kind = kind
        self.frameID = frameID
        self.samples = samples
        self.encodedVoice = encodedVoice
    }

    nonisolated init(
        groupID: UUID,
        streamID: UUID,
        sequenceNumber: Int,
        sentAt: TimeInterval,
        encodedVoice: EncodedVoicePacket
    ) {
        self.groupID = groupID
        self.streamID = streamID
        self.sequenceNumber = sequenceNumber
        self.sentAt = sentAt
        self.kind = .voice
        self.frameID = encodedVoice.frameID
        self.samples = []
        self.encodedVoice = encodedVoice
    }

    nonisolated init(
        groupID: UUID,
        streamID: UUID,
        sequenceNumber: Int,
        sentAt: TimeInterval,
        packet: OutboundAudioPacket
    ) {
        self.groupID = groupID
        self.streamID = streamID
        self.sequenceNumber = sequenceNumber
        self.sentAt = sentAt

        switch packet {
        case .voice(let frameID, let samples):
            if let encodedVoice = try? EncodedVoicePacket.make(frameID: frameID, samples: samples) {
                self.kind = .voice
                self.frameID = frameID
                self.samples = []
                self.encodedVoice = encodedVoice
            } else {
                self.kind = .voice
                self.frameID = frameID
                self.samples = samples
                self.encodedVoice = nil
            }
        case .keepalive:
            self.kind = .voice
            self.frameID = nil
            self.samples = []
            self.encodedVoice = nil
        }
    }

    var packet: OutboundAudioPacket? {
        switch kind {
        case .voice:
            if let encodedVoice,
               let decodedSamples = try? encodedVoice.decodeSamples() {
                return .voice(frameID: encodedVoice.frameID, samples: decodedSamples)
            }
            guard let frameID else { return nil }
            return .voice(frameID: frameID, samples: samples)
        }
    }
}

struct ReceivedAudioPacket: Equatable {
    let peerID: String
    let envelope: AudioPacketEnvelope
    let packet: OutboundAudioPacket
}

struct JitterBufferedAudioFrame: Equatable {
    let peerID: String
    let streamID: UUID
    let sequenceNumber: Int
    let frameID: Int
    let samples: [Float]
}

private struct ReceivedAudioFrameKey: Hashable {
    let peerID: String
    let streamID: UUID
    let sequenceNumber: Int
}

enum RemoteAudioJitterBufferDefaults {
    static let playoutDelay: TimeInterval = 0.015
    static let packetLifetime: TimeInterval = 2.0
}

struct JitterBuffer {
    private let playoutDelay: TimeInterval
    private let packetLifetime: TimeInterval
    private var queuedPackets: [QueuedPacket] = []
    private var seenPacketIDs: Set<PacketID> = []
    private(set) var droppedFrameCount = 0

    var queuedFrameCount: Int {
        queuedPackets.count
    }

    init(
        playoutDelay: TimeInterval = RemoteAudioJitterBufferDefaults.playoutDelay,
        packetLifetime: TimeInterval = RemoteAudioJitterBufferDefaults.packetLifetime
    ) {
        self.playoutDelay = playoutDelay
        self.packetLifetime = packetLifetime
    }

    mutating func enqueue(_ packet: ReceivedAudioPacket, receivedAt: TimeInterval) {
        guard case .voice = packet.packet else { return }

        let packetID = PacketID(
            streamID: packet.envelope.streamID,
            sequenceNumber: packet.envelope.sequenceNumber
        )
        guard seenPacketIDs.insert(packetID).inserted else {
            droppedFrameCount += 1
            return
        }

        queuedPackets.append(QueuedPacket(packet: packet, receivedAt: receivedAt))
    }

    mutating func drainReadyFrames(now: TimeInterval) -> [JitterBufferedAudioFrame] {
        let queuedCountBeforeExpiration = queuedPackets.count
        queuedPackets.removeAll { queuedPacket in
            now - queuedPacket.receivedAt >= packetLifetime
        }
        droppedFrameCount += queuedCountBeforeExpiration - queuedPackets.count

        let readyPackets = queuedPackets
            .filter { now - $0.receivedAt >= playoutDelay }
            .sorted { left, right in
                if left.packet.envelope.streamID != right.packet.envelope.streamID {
                    return left.packet.envelope.streamID.uuidString < right.packet.envelope.streamID.uuidString
                }
                return left.packet.envelope.sequenceNumber < right.packet.envelope.sequenceNumber
            }

        let readyPacketIDs = Set(readyPackets.map {
            PacketID(
                streamID: $0.packet.envelope.streamID,
                sequenceNumber: $0.packet.envelope.sequenceNumber
            )
        })
        queuedPackets.removeAll { queuedPacket in
            readyPacketIDs.contains(
                PacketID(
                    streamID: queuedPacket.packet.envelope.streamID,
                    sequenceNumber: queuedPacket.packet.envelope.sequenceNumber
                )
            )
        }

        return readyPackets.compactMap { queuedPacket in
            guard case .voice(let frameID, let samples) = queuedPacket.packet.packet else { return nil }
            return JitterBufferedAudioFrame(
                peerID: queuedPacket.packet.peerID,
                streamID: queuedPacket.packet.envelope.streamID,
                sequenceNumber: queuedPacket.packet.envelope.sequenceNumber,
                frameID: frameID,
                samples: samples
            )
        }
    }

    private struct QueuedPacket {
        let packet: ReceivedAudioPacket
        let receivedAt: TimeInterval
    }

    private struct PacketID: Hashable {
        let streamID: UUID
        let sequenceNumber: Int
    }
}

protocol AudioFramePlaying: AnyObject {
    func start() throws
    func stop()
    func play(_ frame: JitterBufferedAudioFrame)
    func play(_ frames: [JitterBufferedAudioFrame])
}

enum AudioFrameMixer {
    static func mix(_ frames: [JitterBufferedAudioFrame]) -> [Float] {
        let sampleCount = frames.map(\.samples.count).max() ?? 0
        guard sampleCount > 0 else { return [] }

        return (0..<sampleCount).map { sampleIndex in
            let mixedSample = frames.reduce(Float.zero) { partialResult, frame in
                guard sampleIndex < frame.samples.count else { return partialResult }
                return partialResult + frame.samples[sampleIndex]
            }
            return min(1.0, max(-1.0, mixedSample))
        }
    }
}

protocol AudioOutputRendering: AnyObject {
    func start() throws
    func stop()
    func schedule(samples: [Float])
}

final class BufferedAudioFramePlayer: AudioFramePlaying {
    private let renderer: AudioOutputRendering

    init(renderer: AudioOutputRendering) {
        self.renderer = renderer
    }

    func start() throws {
        try renderer.start()
    }

    func stop() {
        renderer.stop()
    }

    func play(_ frame: JitterBufferedAudioFrame) {
        guard !frame.samples.isEmpty else { return }
        renderer.schedule(samples: frame.samples)
    }

    func play(_ frames: [JitterBufferedAudioFrame]) {
        let samples = AudioFrameMixer.mix(frames)
        guard !samples.isEmpty else { return }
        renderer.schedule(samples: samples)
    }
}

