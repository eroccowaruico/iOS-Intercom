import AVFoundation
import Codec
import CryptoKit
import Foundation
import OSLog
import RTC
import SessionManager
import VADGate

extension IntercomViewModel {
    func handleAvailableAudioPortsChanged() {
        let previousOutputPort = selectedOutputPort
        selectedInputPort = audioSessionManager.selectedInputPort
        selectedOutputPort = audioSessionManager.selectedOutputPort
        if selectedOutputPort != previousOutputPort {
            do {
                try refreshOutputRendererIfNeeded()
                audioErrorMessage = nil
            } catch {
                audioErrorMessage = "Audio output device change failed"
            }
        }
    }

    func refreshOutputRendererIfNeeded() throws {
        guard isAudioReady || audioCheckPhase == .playing else { return }
        audioFramePlayer.stop()
        try audioFramePlayer.start()
    }
}
