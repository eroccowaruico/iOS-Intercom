import CryptoKit
import AVFoundation
import Codec
import Foundation
import Observation
import OSLog
import RTC
import SessionManager
import VADGate

struct AudioLevelMeter {
    static func rmsLevel(samples: [Float]) -> Float {
        VADGate.rms(samples: samples)
    }
}

enum AudioResampler {
    /// Resamples audio samples from one sample rate to another using linear interpolation.
    static func resample(_ samples: [Float], fromRate sourceRate: Double, toRate targetRate: Double) -> [Float] {
        guard !samples.isEmpty, sourceRate > 0, targetRate > 0 else { return samples }
        guard abs(sourceRate - targetRate) > 0.5 else { return samples }

        let ratio = targetRate / sourceRate
        let outputCount = max(1, Int((Double(samples.count) * ratio).rounded()))

        return (0..<outputCount).map { outputIndex in
            let sourcePosition = Double(outputIndex) / ratio
            let lowIndex = Int(sourcePosition)
            let highIndex = min(lowIndex + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lowIndex))
            return samples[lowIndex] * (1 - fraction) + samples[highIndex] * fraction
        }
    }
}

enum PCMAudioCodec {
    nonisolated static func encode(_ samples: [Float]) -> Data {
        PCM16Codec.encode(samples)
    }

    nonisolated static func decode(_ data: Data) throws -> [Float] {
        try PCM16Codec.decode(data)
    }

    enum CodecError: Error, Equatable {
        case invalidByteCount
    }
}

protocol AudioEncoding {
    nonisolated var codec: AudioCodecIdentifier { get }

    nonisolated func encode(_ samples: [Float]) throws -> Data
    nonisolated func decode(_ data: Data) throws -> [Float]
}

struct PCMAudioEncoding: AudioEncoding {
    nonisolated let codec: AudioCodecIdentifier = .pcm16

    nonisolated init() {}

    nonisolated func encode(_ samples: [Float]) throws -> Data {
        PCMAudioCodec.encode(samples)
    }

    nonisolated func decode(_ data: Data) throws -> [Float] {
        try PCMAudioCodec.decode(data)
    }
}
