import AVFoundation

public struct AudioSessionConfiguration: Sendable {
    public let category: AVAudioSession.Category
    public let mode: AVAudioSession.Mode
    public let options: AVAudioSession.CategoryOptions
    public static func defaultOptions(for category: AVAudioSession.Category) -> AVAudioSession.CategoryOptions {
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers]
        #if os(iOS) || os(tvOS)
        if category == .playback {
            options.insert(.allowBluetoothA2DP)
        }
        #endif
        return options
    }

    public init(
        category: AVAudioSession.Category = .playAndRecord,
        mode: AVAudioSession.Mode = .voiceChat,
        options: AVAudioSession.CategoryOptions = AudioSessionConfiguration.defaultOptions(for: category)
    ) {
        self.category = category
        self.mode = mode
        self.options = options
    }
}

public final class AudioSessionManager {
    private let session: AVAudioSession

    public init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    public func activate(configuration: AudioSessionConfiguration = AudioSessionConfiguration()) throws {
        try session.setCategory(configuration.category, mode: configuration.mode, options: configuration.options)
        try session.setActive(true, options: [])
    }

    public func deactivate() throws {
        try session.setActive(false, options: [])
    }
}
