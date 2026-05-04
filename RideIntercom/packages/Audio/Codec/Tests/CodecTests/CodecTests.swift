import AudioToolbox
import Foundation
import Testing
@testable import Codec

@Test func codecIdentifiersExposeExpectedAudioFormatIDs() {
    #expect(CodecIdentifier.pcm16.audioFormatID == kAudioFormatLinearPCM)
    #expect(CodecIdentifier.mpeg4AACELDv2.audioFormatID == kAudioFormatMPEG4AAC_ELD_V2)
    #expect(CodecIdentifier.opus.audioFormatID == kAudioFormatOpus)
}

@Test func defaultConfigurationUsesRideIntercomVoicePreset() {
    let configuration = CodecEncodingConfiguration()

    #expect(configuration.codec == .pcm16)
    #expect(configuration.format == CodecAudioFormat(sampleRate: 48_000, channelCount: 1))
    #expect(configuration.aacELDv2Options.bitRate == 24_000)
    #expect(configuration.opusOptions.bitRate == 32_000)
}

@Test func formatClampsToSupportedVoiceRanges() {
    let low = CodecAudioFormat(sampleRate: 1_000, channelCount: 0)
    let high = CodecAudioFormat(sampleRate: 192_000, channelCount: 8)

    #expect(low.sampleRate == 8_000)
    #expect(low.channelCount == 1)
    #expect(high.sampleRate == 96_000)
    #expect(high.channelCount == 2)
}

@Test func codecSpecificOptionsClampBitRates() {
    #expect(AACELDv2Options(bitRate: 1_000).bitRate == 12_000)
    #expect(AACELDv2Options(bitRate: 256_000).bitRate == 128_000)
    #expect(OpusOptions(bitRate: 1_000).bitRate == 6_000)
    #expect(OpusOptions(bitRate: 256_000).bitRate == 128_000)
}

@Test func pcm16EncodingUsesSignedLittleEndianSamples() throws {
    let data = PCM16Codec.encode([-1, -0.5, 0, 0.5, 1])

    #expect(Array(data) == [
        0x00, 0x80,
        0x00, 0xc0,
        0x00, 0x00,
        0x00, 0x40,
        0xff, 0x7f,
    ])

    let decoded = try PCM16Codec.decode(data)
    #expect(decoded[0] == -1)
    #expect(abs(decoded[1] - -0.5) < 0.000_1)
    #expect(decoded[2] == 0)
    #expect(abs(decoded[3] - 0.5) < 0.000_1)
    #expect(decoded[4] == 1)
}

@Test func pcm16EncodingClampsOutOfRangeSamples() throws {
    let decoded = try PCM16Codec.decode(PCM16Codec.encode([-2, 2]))

    #expect(decoded == [-1, 1])
}

@Test func pcm16DecodeRejectsOddByteCounts() {
    do {
        _ = try PCM16Codec.decode(Data([0x00]))
        Issue.record("PCM16 decode must reject odd byte counts")
    } catch {
        #expect(error as? CodecError == .invalidByteCount)
    }
}

@Test func encoderProducesTransportablePCMFrames() throws {
    let encoder = CodecEncoder()
    let frame = try encoder.encode(
        PCMCodecFrame(
            sequenceNumber: 42,
            format: CodecAudioFormat(sampleRate: 48_000, channelCount: 1),
            capturedAt: 123,
            samples: [0, 0.25, -0.25]
        )
    )

    #expect(frame.sequenceNumber == 42)
    #expect(frame.codec == .pcm16)
    #expect(frame.format.sampleRate == 48_000)
    #expect(frame.capturedAt == 123)
    #expect(frame.sampleCount == 3)
    #expect(frame.payload == PCM16Codec.encode([0, 0.25, -0.25]))
}

@Test func decoderSelectsCodecFromFrameMetadata() throws {
    let codec = AudioCodec()
    let encoded = try codec.encode(sequenceNumber: 9, samples: [0.1, -0.1], capturedAt: 456)
    let decoded = try codec.decode(encoded)

    #expect(decoded.sequenceNumber == 9)
    #expect(decoded.format == encoded.format)
    #expect(decoded.capturedAt == 456)
    #expect(decoded.samples.count == 2)
    #expect(abs(decoded.samples[0] - 0.1) < 0.000_1)
    #expect(abs(decoded.samples[1] - -0.1) < 0.000_1)
}

@Test func compressedDecoderRejectsNonCodecPayloads() {
    let frame = EncodedCodecFrame(
        sequenceNumber: 1,
        codec: .opus,
        format: CodecAudioFormat(),
        capturedAt: 0,
        sampleCount: 0,
        payload: Data([0xde, 0xad, 0xbe, 0xef])
    )

    do {
        _ = try CodecDecoder().decode(frame)
        Issue.record("Compressed codecs must reject payloads that do not include Codec packet metadata")
    } catch {
        #expect(error as? CodecError == .malformedPayload(.opus))
    }
}

@Test func supportReportsPCMAlwaysAvailable() {
    #expect(CodecSupport.isEncodingAvailable(for: CodecEncodingConfiguration(codec: .pcm16)))
    #expect(CodecSupport.isDecodingAvailable(for: .pcm16))
}
