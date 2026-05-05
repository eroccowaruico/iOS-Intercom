import Codec
import Foundation
import RTC

enum OutboundAudioPacket: Equatable {
    case voice(frameID: Int, samples: [Float] = [])
    case keepalive
}

typealias AudioCodecIdentifier = RTC.AudioCodecIdentifier

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

final class AppAudioCodecOptions: @unchecked Sendable {
    private let lock = NSLock()
    private var aacELDv2BitRate: Int
    private var opusBitRate: Int

    init(aacELDv2BitRate: Int = 32_000, opusBitRate: Int = 32_000) {
        self.aacELDv2BitRate = Codec.AACELDv2Options(bitRate: aacELDv2BitRate).bitRate
        self.opusBitRate = Codec.OpusOptions(bitRate: opusBitRate).bitRate
    }

    func update(aacELDv2BitRate: Int, opusBitRate: Int) {
        lock.withLock {
            self.aacELDv2BitRate = Codec.AACELDv2Options(bitRate: aacELDv2BitRate).bitRate
            self.opusBitRate = Codec.OpusOptions(bitRate: opusBitRate).bitRate
        }
    }

    var aacELDv2Options: Codec.AACELDv2Options {
        lock.withLock { Codec.AACELDv2Options(bitRate: aacELDv2BitRate) }
    }

    var opusOptions: Codec.OpusOptions {
        lock.withLock { Codec.OpusOptions(bitRate: opusBitRate) }
    }
}

private struct PackageAudioFrameCodec: RTC.AudioFrameCodec {
    let identifier: RTC.AudioCodecIdentifier
    private let codecIdentifier: Codec.CodecIdentifier
    private let options: AppAudioCodecOptions

    init(
        codecIdentifier: Codec.CodecIdentifier,
        options: AppAudioCodecOptions
    ) {
        self.identifier = codecIdentifier.rtcIdentifier
        self.codecIdentifier = codecIdentifier
        self.options = options
    }

    func encode(_ frame: RTC.AudioFrame) throws -> RTC.EncodedAudioFrame {
        let codecFormat = Codec.CodecAudioFormat(rtcFormat: frame.format)
        let configuration = Codec.CodecEncodingConfiguration(
            codec: codecIdentifier,
            format: codecFormat,
            aacELDv2Options: options.aacELDv2Options,
            opusOptions: options.opusOptions
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
    static func makeRTCCodecRegistry(
        format: RTC.AudioFormatDescriptor,
        options: AppAudioCodecOptions = AppAudioCodecOptions()
    ) -> RTC.AudioCodecRegistry {
        var codecs: [any RTC.AudioFrameCodec] = [RTC.PCM16AudioCodec()]
        for codecIdentifier in [Codec.CodecIdentifier.mpeg4AACELDv2, .opus]
        where isAvailable(codecIdentifier, format: format) {
            codecs.append(PackageAudioFrameCodec(codecIdentifier: codecIdentifier, options: options))
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
