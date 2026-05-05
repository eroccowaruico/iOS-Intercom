import Testing
@testable import SessionManager

#if canImport(AVFAudio)
import AVFAudio
#endif

@Test func audioStreamFormatNormalizesAndReportsLevel() {
    let format = AudioStreamFormat(sampleRate: 2_000, channelCount: 5)
    let frame = AudioStreamFrame(
        sequenceNumber: 7,
        format: format,
        capturedAt: 10,
        samples: [0.25, -0.5, 1.0, -1.0]
    )

    #expect(format.sampleRate == 8_000)
    #expect(format.channelCount == 2)
    #expect(frame.level.peak == 1.0)
    #expect(frame.level.rms > 0.76)
    #expect(frame.level.rms < 0.77)
}

@Test func inputCaptureReportsOperationsAndRealtimeFrames() {
    let backend = FakeInputStreamBackend()
    let configuration = AudioInputStreamConfiguration(
        format: AudioStreamFormat(sampleRate: 16_000, channelCount: 1),
        bufferFrameCount: 0
    )
    let capture = AudioInputStreamCapture(configuration: configuration, backend: backend)
    var events: [AudioStreamRuntimeEvent] = []
    capture.setRuntimeEventHandler { event in
        events.append(event)
    }

    let start = capture.start()
    backend.emit(AudioStreamFrame(sequenceNumber: 1, format: configuration.format, capturedAt: 10, samples: [0.1]))
    let stop = capture.stop()
    let secondStop = capture.stop()

    #expect(configuration.bufferFrameCount == 1)
    #expect(start.result == .applied)
    #expect(stop.result == .applied)
    #expect(secondStop.result == .ignored(.alreadyStopped))
    #expect(start.snapshot.isRunning)
    #expect(stop.snapshot.isRunning == false)
    #expect(secondStop.snapshot.processedFrameCount == 1)
    #expect(backend.startCount == 1)
    #expect(backend.stopCount == 1)
    #expect(events.contains(.inputFrame(AudioStreamFrame(
        sequenceNumber: 1,
        format: configuration.format,
        capturedAt: 10,
        samples: [0.1]
    ))))
}

@Test func inputCaptureMapsUnsupportedBackendToIgnoredReport() {
    let backend = FakeInputStreamBackend()
    backend.startError = AudioStreamError.unsupportedOnCurrentPlatform
    let capture = AudioInputStreamCapture(backend: backend)

    let report = capture.start()

    #expect(report.result == .ignored(.unsupportedOnCurrentPlatform))
    #expect(report.snapshot.isRunning == false)
}

@Test func outputRendererReportsScheduleAndRejectsMismatchedFormat() {
    let backend = FakeOutputStreamBackend()
    let configuration = AudioOutputStreamConfiguration(format: AudioStreamFormat(sampleRate: 16_000, channelCount: 1))
    let renderer = AudioOutputStreamRenderer(configuration: configuration, backend: backend)
    var events: [AudioStreamRuntimeEvent] = []
    renderer.setRuntimeEventHandler { event in
        events.append(event)
    }

    let start = renderer.start()
    let scheduled = renderer.schedule(AudioStreamFrame(
        sequenceNumber: 1,
        format: configuration.format,
        capturedAt: 10,
        samples: [0.2, 0.3]
    ))
    let rejected = renderer.schedule(AudioStreamFrame(
        sequenceNumber: 2,
        format: AudioStreamFormat(sampleRate: 48_000, channelCount: 1),
        capturedAt: 10,
        samples: [0.4]
    ))

    #expect(start.result == .applied)
    #expect(scheduled.result == .applied)
    #expect(scheduled.snapshot.processedFrameCount == 1)
    #expect(backend.scheduledFrames.map(\.sequenceNumber) == [1])
    guard case .failed(.invalidFrame) = rejected.result else {
        Issue.record("Expected invalid frame failure")
        return
    }
    #expect(events.contains(.outputFrameScheduled(AudioStreamFrame(
        sequenceNumber: 1,
        format: configuration.format,
        capturedAt: 10,
        samples: [0.2, 0.3]
    ))))
}

#if canImport(AVFAudio)
@Test func audioStreamFrameRoundTripsThroughPCMBuffer() throws {
    let frame = AudioStreamFrame(
        sequenceNumber: 3,
        format: AudioStreamFormat(sampleRate: 16_000, channelCount: 2),
        capturedAt: 20,
        samples: [0.1, -0.1, 0.2, -0.2]
    )

    let buffer = try frame.makePCMBuffer()
    let restored = try #require(AudioStreamFrame(
        buffer: buffer,
        sequenceNumber: frame.sequenceNumber,
        targetFormat: frame.format,
        capturedAt: frame.capturedAt
    ))

    #expect(restored == frame)
}
#endif

private final class FakeInputStreamBackend: AudioInputStreamBackend {
    var startCount = 0
    var stopCount = 0
    var startError: Error?
    var stopError: Error?
    var onFrame: ((AudioStreamFrame) -> Void)?

    func startCapture(
        configuration: AudioInputStreamConfiguration,
        onFrame: @escaping (AudioStreamFrame) -> Void
    ) throws {
        startCount += 1
        if let startError {
            throw startError
        }
        self.onFrame = onFrame
    }

    func stopCapture() throws {
        stopCount += 1
        if let stopError {
            throw stopError
        }
        onFrame = nil
    }

    func emit(_ frame: AudioStreamFrame) {
        onFrame?(frame)
    }
}

private final class FakeOutputStreamBackend: AudioOutputStreamBackend {
    var startCount = 0
    var stopCount = 0
    var scheduledFrames: [AudioStreamFrame] = []
    var startError: Error?
    var stopError: Error?
    var scheduleError: Error?

    func startRendering(configuration: AudioOutputStreamConfiguration) throws {
        startCount += 1
        if let startError {
            throw startError
        }
    }

    func stopRendering() throws {
        stopCount += 1
        if let stopError {
            throw stopError
        }
    }

    func schedule(_ frame: AudioStreamFrame) throws {
        if let scheduleError {
            throw scheduleError
        }
        scheduledFrames.append(frame)
    }
}
