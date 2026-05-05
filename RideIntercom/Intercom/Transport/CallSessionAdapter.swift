import CryptoKit
import AVFoundation
import Codec
import Foundation
import Observation
import OSLog
import RTC
import SessionManager
import VADGate

enum ControlMessage: Equatable {
    case keepalive
    case peerMuteState(isMuted: Bool)
}

typealias ApplicationDataDelivery = RTC.ApplicationDataDelivery
typealias ApplicationDataMessage = RTC.ApplicationDataMessage

enum LocalNetworkRejectReason: String, Equatable {
    case groupMismatch = "group mismatch"
    case handshakeInvalid = "handshake invalid"
}

enum LocalNetworkStatus: Equatable {
    case idle
    case advertisingBrowsing
    case invited
    case invitationReceived
    case connected
    case rejected(LocalNetworkRejectReason)
    case unavailable

    var label: String {
        switch self {
        case .idle:
            "MC idle"
        case .advertisingBrowsing:
            "MC advertising+browsing"
        case .invited:
            "MC invited"
        case .invitationReceived:
            "MC invitation"
        case .connected:
            "MC connected"
        case .rejected(let reason):
            "MC rejected: \(reason.rawValue)"
        case .unavailable:
            "MC unavailable"
        }
    }
}

struct LocalNetworkEvent: Equatable {
    let status: LocalNetworkStatus
    let peerID: String?
    let occurredAt: TimeInterval?

    nonisolated init(status: LocalNetworkStatus, peerID: String? = nil, occurredAt: TimeInterval? = nil) {
        self.status = status
        self.peerID = peerID
        self.occurredAt = occurredAt
    }
}


enum TransportEvent: Equatable {
    case localNetworkStatus(LocalNetworkEvent)
    case connected(peerIDs: [String])
    case authenticated(peerIDs: [String])
    case remotePeerMuteState(peerID: String, isMuted: Bool)
    case remotePeerMetadata(peerID: String, activeCodec: AudioCodecIdentifier?)
    case receivedApplicationData(peerID: String, message: ApplicationDataMessage)
    case disconnected
    case linkFailed(internetAvailable: Bool)
    case receivedAudioFrame(RTC.ReceivedAudioFrame)
    case routeMetrics(RTC.RouteMetrics)
}

protocol CallSession: AnyObject {
    var onEvent: ((TransportEvent) -> Void)? { get set }
    var activeRouteDebugTypeName: String { get }

    func startStandby(group: IntercomGroup)
    func connect(group: IntercomGroup)
    func startMedia()
    func stopMedia()
    func disconnect()
    func setPreferredAudioCodec(_ codec: AudioCodecIdentifier)
    func setAudioCodecOptions(aacELDv2BitRate: Int, opusBitRate: Int)
    func setLocalMute(_ muted: Bool)
    func setOutputMute(_ muted: Bool)
    func setRemoteOutputVolume(peerID: String, volume: Float)
    func sendAudioFrame(_ frame: OutboundAudioPacket)
    func sendControl(_ message: ControlMessage)
    func sendApplicationData(_ message: ApplicationDataMessage)
}

private struct PeerMuteStateApplicationPayload: Codable, Equatable {
    let isMuted: Bool
}

private struct PeerMetadataApplicationPayload: Codable, Equatable {
    let activeCodec: AudioCodecIdentifier?
}

final class RideIntercomCallSessionAdapter: CallSession {
    var onEvent: ((TransportEvent) -> Void)?
    private(set) var activeRouteDebugTypeName: String = "RTC RouteManager"

    private nonisolated static let keepaliveNamespace = "rideintercom.keepalive"
    private nonisolated static let peerMuteStateNamespace = "rideintercom.peerMuteState"
    private let memberID: String
    private let rtcSession: RTC.CallSession
    private let audioCodecOptions: AppAudioCodecOptions
    private var eventTask: Task<Void, Never>?
    private var preferredAudioCodec: AudioCodecIdentifier = .pcm16

    init(memberID: String) {
        self.memberID = memberID
        let audioCodecOptions = AppAudioCodecOptions()
        self.audioCodecOptions = audioCodecOptions
        #if canImport(MultipeerConnectivity)
        self.rtcSession = RTC.RouteManager(
            routes: [
                RTC.MultipeerLocalRoute(
                    displayName: memberID,
                    codecRegistry: AppAudioCodecBridge.makeRTCCodecRegistry(
                        format: .intercomPacketAudio,
                        options: audioCodecOptions
                    )
                )
            ],
            configuration: RTC.CallRouteConfiguration(
                enabledRoutes: [.multipeer],
                preferredRoute: .multipeer,
                selectionMode: .singleRoute,
                keepsPreferredRouteInStandby: false,
                keepsFallbackRouteWarm: false
            )
        )
        #else
        self.rtcSession = RTC.UnavailableCallSession()
        #endif
        bindEvents()
    }

    init(memberID: String = "member-local", rtcSession: RTC.CallSession) {
        self.memberID = memberID
        self.audioCodecOptions = AppAudioCodecOptions()
        self.rtcSession = rtcSession
        bindEvents()
    }

    deinit {
        eventTask?.cancel()
    }

    func startStandby(group: IntercomGroup) {
        Task { [rtcSession, request = makeRTCRequest(from: group)] in
            await rtcSession.prepare(request)
        }
    }

    func connect(group: IntercomGroup) {
        Task { [rtcSession, request = makeRTCRequest(from: group)] in
            await rtcSession.prepare(request)
            await rtcSession.startConnection()
        }
    }

    func startMedia() {
        Task { [rtcSession] in
            await rtcSession.startMedia()
        }
    }

    func stopMedia() {
        Task { [rtcSession] in
            await rtcSession.stopMedia()
        }
    }

    func disconnect() {
        Task { [rtcSession] in
            await rtcSession.stopConnection()
        }
    }

    func setPreferredAudioCodec(_ codec: AudioCodecIdentifier) {
        preferredAudioCodec = AppAudioCodecBridge.resolvedPreferredCodec(codec, format: .intercomPacketAudio)
    }

    func setAudioCodecOptions(aacELDv2BitRate: Int, opusBitRate: Int) {
        audioCodecOptions.update(aacELDv2BitRate: aacELDv2BitRate, opusBitRate: opusBitRate)
    }

    func setLocalMute(_ muted: Bool) {
        Task { [rtcSession] in
            await rtcSession.setLocalMute(muted)
        }
    }

    func setOutputMute(_ muted: Bool) {
        Task { [rtcSession] in
            await rtcSession.setOutputMute(muted)
        }
    }

    func setRemoteOutputVolume(peerID: String, volume: Float) {
        Task { [rtcSession] in
            await rtcSession.setRemoteOutputVolume(peerID: RTC.PeerID(rawValue: peerID), volume: volume)
        }
    }

    func sendAudioFrame(_ frame: OutboundAudioPacket) {
        guard case .voice(let frameID, let samples) = frame else {
            sendControl(.keepalive)
            return
        }

        let sequenceNumber = UInt64(max(0, frameID))
        let audioFrame = RTC.AudioFrame(
            sequenceNumber: sequenceNumber,
            format: RTC.AudioFormatDescriptor(sampleRate: 16_000, channelCount: 1),
            capturedAt: Date().timeIntervalSince1970,
            samples: samples
        )
        Task { [rtcSession] in
            await rtcSession.sendAudioFrame(audioFrame)
        }
    }

    func sendControl(_ message: ControlMessage) {
        switch message {
        case .keepalive:
            let payload = try? JSONEncoder().encode(PeerMetadataApplicationPayload(activeCodec: preferredAudioCodec))
            sendApplicationData(ApplicationDataMessage(
                namespace: Self.keepaliveNamespace,
                payload: payload ?? Data(),
                delivery: .unreliable
            ))
        case .peerMuteState(let isMuted):
            sendPeerMuteState(isMuted: isMuted)
        }
    }

    func sendApplicationData(_ message: ApplicationDataMessage) {
        Task { [rtcSession] in
            await rtcSession.sendApplicationData(message)
        }
    }

    private func bindEvents() {
        eventTask?.cancel()
        eventTask = Task { [weak self, rtcSession] in
            for await event in rtcSession.events {
                self?.handleRTCEvent(event)
            }
        }
    }

    private func handleRTCEvent(_ event: RTC.CallSessionEvent) {
        switch event {
        case .stateChanged(let state):
            handleRTCStateChanged(state)
        case .routeChanged(let snapshot):
            activeRouteDebugTypeName = Self.routeDebugName(snapshot.activeRoute ?? snapshot.mediaRoute)
        case .routeAvailabilityChanged:
            break
        case .membersChanged(let members):
            let peerIDs = members.map { $0.peer.id.rawValue }.filter { $0 != memberID }.sorted()
            onEvent?(.connected(peerIDs: peerIDs))
            onEvent?(.authenticated(peerIDs: peerIDs))
        case .receivedApplicationData(let received):
            onEvent?(Self.makeAppEvent(peerID: received.peerID.rawValue, applicationData: received.message))
        case .receivedAudioFrame(let received):
            onEvent?(.receivedAudioFrame(received))
        case .metricsChanged(let metrics):
            onEvent?(.routeMetrics(metrics))
        case .localAudioLevelChanged, .remoteAudioLevelChanged:
            break
        case .error:
            onEvent?(.linkFailed(internetAvailable: false))
        }
    }

    private func handleRTCStateChanged(_ state: RTC.CallConnectionState) {
        switch state {
        case .idle:
            onEvent?(.localNetworkStatus(LocalNetworkEvent(status: .idle, occurredAt: Date().timeIntervalSince1970)))
        case .preparing, .connecting:
            onEvent?(.localNetworkStatus(LocalNetworkEvent(status: .advertisingBrowsing, occurredAt: Date().timeIntervalSince1970)))
        case .connected, .mediaReady:
            onEvent?(.localNetworkStatus(LocalNetworkEvent(status: .connected, occurredAt: Date().timeIntervalSince1970)))
        case .reconnecting:
            onEvent?(.linkFailed(internetAvailable: true))
        case .disconnected:
            onEvent?(.disconnected)
        case .failed:
            onEvent?(.linkFailed(internetAvailable: false))
        }
    }

    private func sendPeerMuteState(isMuted: Bool) {
        guard let payload = try? JSONEncoder().encode(PeerMuteStateApplicationPayload(isMuted: isMuted)) else { return }
        sendApplicationData(ApplicationDataMessage(
            namespace: Self.peerMuteStateNamespace,
            payload: payload,
            delivery: .reliable
        ))
    }

    private static func makeAppEvent(peerID: String, applicationData message: RTC.ApplicationDataMessage) -> TransportEvent {
        if message.namespace == peerMuteStateNamespace,
           let payload = try? JSONDecoder().decode(PeerMuteStateApplicationPayload.self, from: message.payload) {
            return .remotePeerMuteState(peerID: peerID, isMuted: payload.isMuted)
        }
        if message.namespace == keepaliveNamespace,
           let payload = try? JSONDecoder().decode(PeerMetadataApplicationPayload.self, from: message.payload) {
            return .remotePeerMetadata(peerID: peerID, activeCodec: payload.activeCodec)
        }

        return .receivedApplicationData(peerID: peerID, message: message)
    }

    private func makeRTCRequest(from group: IntercomGroup) -> RTC.CallStartRequest {
        let localMember = group.members.first(where: { $0.id == memberID })
        let localPeer = RTC.PeerDescriptor(
            id: RTC.PeerID(rawValue: memberID),
            displayName: localMember?.displayName ?? memberID
        )
        let expectedPeers = group.members
            .filter { $0.id != memberID }
            .map { RTC.PeerDescriptor(id: RTC.PeerID(rawValue: $0.id), displayName: $0.displayName) }
        return RTC.CallStartRequest(
            sessionID: group.id.uuidString,
            localPeer: localPeer,
            expectedPeers: expectedPeers,
            credential: group.accessSecret.map { RTC.RTCCredential.derived(groupID: group.id.uuidString, secret: $0) },
            configuration: RTC.CallRouteConfiguration(
                enabledRoutes: [.multipeer],
                preferredRoute: .multipeer,
                selectionMode: .singleRoute,
                keepsPreferredRouteInStandby: false,
                keepsFallbackRouteWarm: false
            ),
            audioFormat: RTC.AudioFormatDescriptor(sampleRate: 16_000, channelCount: 1),
            audioCodecConfiguration: RTC.AudioCodecConfiguration(
                preferredCodecs: AppAudioCodecBridge.preferredRTCCodecs(
                    preferredAudioCodec,
                    format: .intercomPacketAudio
                )
            )
        )
    }

    private static func routeDebugName(_ route: RTC.RouteKind?) -> String {
        switch route {
        case .multipeer:
            "MultipeerLocalRoute"
        case .webRTC:
            "WebRTCInternetRoute"
        case nil:
            "RTC RouteManager"
        }
    }
}
