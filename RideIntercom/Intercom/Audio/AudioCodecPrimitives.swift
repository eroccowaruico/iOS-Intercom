import VADGate

struct AudioLevelMeter {
    static func rmsLevel(samples: [Float]) -> Float {
        VADGate.rms(samples: samples)
    }
}
