import AVFoundation
import Codec
import CryptoKit
import Foundation
import OSLog
import RTC
import SessionManager
import VADGate

extension IntercomViewModel {
    func receptionDebugSummary(now: TimeInterval) -> String {
        diagnosticsSnapshot.reception.summary(now: now)
    }

    func localNetworkDebugSummary(now: TimeInterval = Date().timeIntervalSince1970) -> String {
        diagnosticsSnapshot.localNetwork.summary(now: now)
    }

    func realDeviceCallDebugSummary(now: TimeInterval) -> String {
        let audioReadiness = isAudioReady ? "AUDIO READY" : "AUDIO IDLE"
        return "CALL \(connectionLabel) / \(audioReadiness) / \(audioDebugSummary) / \(authenticationDebugSummary) / \(receptionDebugSummary(now: now))"
    }
}
