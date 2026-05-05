import CryptoKit
import AVFoundation
import Codec
import Foundation
import Observation
import OSLog
import RTC
import SessionManager
import VADGate

enum TransportRoute: String, Equatable {
    case local = "Local"
    case internet = "Internet"
}

enum CallConnectionState: Equatable {
    case idle
    case localConnecting
    case localConnected
    case internetConnecting
    case internetConnected
    case reconnectingOffline

    var label: String {
        switch self {
        case .idle:
            "Idle"
        case .localConnecting:
            "Local Connecting"
        case .localConnected:
            "Local Connected"
        case .internetConnecting:
            "Internet Connecting"
        case .internetConnected:
            "Internet Connected"
        case .reconnectingOffline:
            "Reconnecting / Offline"
        }
    }
}

