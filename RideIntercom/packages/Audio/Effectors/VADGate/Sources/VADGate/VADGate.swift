import Foundation

public enum VADGateState: Equatable, Sendable {
	case silence
	case speech
}

public struct VADGateConfiguration: Equatable, Sendable {
	public var attackDuration: Double
	public var releaseDuration: Double
	public var updateInterval: Double
	public var speechThresholdOffsetDB: Float
	public var silenceThresholdOffsetDB: Float
	public var initialNoiseFloorDBFS: Float
	public var minimumNoiseFloorDBFS: Float
	public var maximumNoiseFloorDBFS: Float
	public var noiseFloorAdaptation: Float
	public var speechGain: Float
	public var silenceGain: Float
	public var gainAttackDuration: Double
	public var gainReleaseDuration: Double

	public init(
		attackDuration: Double = 0.08,
		releaseDuration: Double = 0.5,
		updateInterval: Double = 0.02,
		speechThresholdOffsetDB: Float = 12,
		silenceThresholdOffsetDB: Float = 8,
		initialNoiseFloorDBFS: Float = -60,
		minimumNoiseFloorDBFS: Float = -90,
		maximumNoiseFloorDBFS: Float = -20,
		noiseFloorAdaptation: Float = 0.05,
		speechGain: Float = 1,
		silenceGain: Float = 0,
		gainAttackDuration: Double = 0.03,
		gainReleaseDuration: Double = 0.12
	) {
		let noiseFloorLowerBound = min(minimumNoiseFloorDBFS, maximumNoiseFloorDBFS)
		let noiseFloorUpperBound = max(minimumNoiseFloorDBFS, maximumNoiseFloorDBFS)
		let normalizedSpeechThresholdOffsetDB = Self.clamp(speechThresholdOffsetDB, 1...40)

		self.attackDuration = Self.clamp(attackDuration, 0.01...1)
		self.releaseDuration = Self.clamp(releaseDuration, 0.05...2)
		self.updateInterval = Self.clamp(updateInterval, 0.005...0.1)
		self.speechThresholdOffsetDB = normalizedSpeechThresholdOffsetDB
		self.silenceThresholdOffsetDB = Self.clamp(silenceThresholdOffsetDB, 0...normalizedSpeechThresholdOffsetDB)
		self.initialNoiseFloorDBFS = Self.clamp(initialNoiseFloorDBFS, noiseFloorLowerBound...noiseFloorUpperBound)
		self.minimumNoiseFloorDBFS = noiseFloorLowerBound
		self.maximumNoiseFloorDBFS = noiseFloorUpperBound
		self.noiseFloorAdaptation = Self.clamp(noiseFloorAdaptation, 0...1)
		self.speechGain = Self.clamp(speechGain, 0...1)
		self.silenceGain = Self.clamp(silenceGain, 0...1)
		self.gainAttackDuration = Self.clamp(gainAttackDuration, 0.001...1)
		self.gainReleaseDuration = Self.clamp(gainReleaseDuration, 0.001...2)
	}

	private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
		min(max(value, range.lowerBound), range.upperBound)
	}

	private static func clamp(_ value: Float, _ range: ClosedRange<Float>) -> Float {
		min(max(value, range.lowerBound), range.upperBound)
	}
}

public struct VADGateAnalysis: Equatable, Sendable {
	public var state: VADGateState
	public var rms: Float
	public var rmsDBFS: Float
	public var noiseFloorDBFS: Float
	public var speechThresholdDBFS: Float
	public var silenceThresholdDBFS: Float
	public var gain: Float
}

public final class VADGate {
	public private(set) var configuration: VADGateConfiguration
	public private(set) var state: VADGateState = .silence
	public private(set) var noiseFloorDBFS: Float
	public private(set) var gain: Float

	private var attackElapsed: Double = 0
	private var releaseElapsed: Double = 0

	public init(configuration: VADGateConfiguration = VADGateConfiguration()) {
		self.configuration = configuration
		self.noiseFloorDBFS = configuration.initialNoiseFloorDBFS
		self.gain = configuration.silenceGain
	}

	public func reset(noiseFloorDBFS: Float? = nil) {
		state = .silence
		attackElapsed = 0
		releaseElapsed = 0
		self.noiseFloorDBFS = noiseFloorDBFS ?? configuration.initialNoiseFloorDBFS
		gain = configuration.silenceGain
	}

	@discardableResult
	public func process(samples: [Float], duration: Double? = nil) -> VADGateAnalysis {
		process(rmsDBFS: Self.rmsDBFS(samples: samples), duration: duration)
	}

	@discardableResult
	public func process(rmsDBFS: Float, duration: Double? = nil) -> VADGateAnalysis {
		let frameDuration = duration ?? configuration.updateInterval
		let speechThreshold = noiseFloorDBFS + configuration.speechThresholdOffsetDB
		let silenceThreshold = noiseFloorDBFS + configuration.silenceThresholdOffsetDB

		switch state {
		case .silence:
			if rmsDBFS > speechThreshold {
				attackElapsed += frameDuration
				if attackElapsed >= configuration.attackDuration {
					state = .speech
					attackElapsed = 0
					releaseElapsed = 0
				}
			} else {
				attackElapsed = 0
				adaptNoiseFloor(toward: rmsDBFS)
			}
		case .speech:
			if rmsDBFS < silenceThreshold {
				releaseElapsed += frameDuration
				if releaseElapsed >= configuration.releaseDuration {
					state = .silence
					releaseElapsed = 0
					attackElapsed = 0
				}
			} else {
				releaseElapsed = 0
			}
		}

		updateGain(duration: frameDuration)
		return makeAnalysis(rmsDBFS: rmsDBFS)
	}

	@discardableResult
	public func applyGate(to samples: inout [Float], duration: Double? = nil) -> VADGateAnalysis {
		let analysis = process(samples: samples, duration: duration)
		for index in samples.indices {
			samples[index] *= analysis.gain
		}
		return analysis
	}

	public static func rms(samples: [Float]) -> Float {
		guard !samples.isEmpty else {
			return 0
		}

		let sumOfSquares = samples.reduce(Float(0)) { partial, sample in
			partial + sample * sample
		}
		return (sumOfSquares / Float(samples.count)).squareRoot()
	}

	public static func rmsDBFS(samples: [Float]) -> Float {
		let value = max(rms(samples: samples), 0.000_001)
		return 20 * log10(value)
	}

	private func adaptNoiseFloor(toward rmsDBFS: Float) {
		let adapted = noiseFloorDBFS + (rmsDBFS - noiseFloorDBFS) * configuration.noiseFloorAdaptation
		noiseFloorDBFS = min(max(adapted, configuration.minimumNoiseFloorDBFS), configuration.maximumNoiseFloorDBFS)
	}

	private func updateGain(duration: Double) {
		let targetGain = state == .speech ? configuration.speechGain : configuration.silenceGain
		let rampDuration = state == .speech ? configuration.gainAttackDuration : configuration.gainReleaseDuration
		let step = rampDuration <= 0 ? 1 : min(1, Float(duration / rampDuration))
		gain += (targetGain - gain) * step
		gain = min(max(gain, min(configuration.silenceGain, configuration.speechGain)), max(configuration.silenceGain, configuration.speechGain))
	}

	private func makeAnalysis(rmsDBFS: Float) -> VADGateAnalysis {
		VADGateAnalysis(
			state: state,
			rms: pow(10, rmsDBFS / 20),
			rmsDBFS: rmsDBFS,
			noiseFloorDBFS: noiseFloorDBFS,
			speechThresholdDBFS: noiseFloorDBFS + configuration.speechThresholdOffsetDB,
			silenceThresholdDBFS: noiseFloorDBFS + configuration.silenceThresholdOffsetDB,
			gain: gain
		)
	}
}
