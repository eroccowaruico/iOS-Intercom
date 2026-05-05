import Codec
import Foundation
import RTC

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
