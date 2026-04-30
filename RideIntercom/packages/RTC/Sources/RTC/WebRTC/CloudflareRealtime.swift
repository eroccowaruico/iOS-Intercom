import Foundation

public struct CloudflareRealtimeConfiguration: Codable, Equatable, Sendable {
    public var sfuEndpoint: URL
    public var turnEndpoint: URL?
    public var roomID: String
    public var participantToken: String
    public var iceServers: [WebRTCIceServer]

    public init(
        sfuEndpoint: URL,
        turnEndpoint: URL? = nil,
        roomID: String,
        participantToken: String,
        iceServers: [WebRTCIceServer] = []
    ) {
        self.sfuEndpoint = sfuEndpoint
        self.turnEndpoint = turnEndpoint
        self.roomID = roomID
        self.participantToken = participantToken
        self.iceServers = iceServers
    }
}

public struct WebRTCIceServer: Codable, Equatable, Sendable {
    public var urls: [String]
    public var username: String?
    public var credential: String?

    public init(urls: [String], username: String? = nil, credential: String? = nil) {
        self.urls = urls
        self.username = username
        self.credential = credential
    }
}

public struct WebRTCSessionDescription: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case offer
        case answer
    }

    public var kind: Kind
    public var sdp: String

    public init(kind: Kind, sdp: String) {
        self.kind = kind
        self.sdp = sdp
    }
}

public struct WebRTCIceCandidate: Codable, Equatable, Sendable {
    public var sdp: String
    public var sdpMid: String?
    public var sdpMLineIndex: Int32

    public init(sdp: String, sdpMid: String?, sdpMLineIndex: Int32) {
        self.sdp = sdp
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }
}

public struct WebRTCSignalingConnectRequest: Equatable, Sendable {
    public var call: CallStartRequest
    public var cloudflare: CloudflareRealtimeConfiguration

    public init(call: CallStartRequest, cloudflare: CloudflareRealtimeConfiguration) {
        self.call = call
        self.cloudflare = cloudflare
    }
}

public enum WebRTCSignalingEvent: Equatable, Sendable {
    case connected
    case disconnected
    case remotePeerJoined(PeerDescriptor)
    case remotePeerLeft(PeerID)
    case offer(WebRTCSessionDescription, from: PeerID)
    case answer(WebRTCSessionDescription, from: PeerID)
    case iceCandidate(WebRTCIceCandidate, from: PeerID)
    case receivedApplicationData(ReceivedApplicationData)
    case failed(String)
}

public protocol WebRTCSignalingClient: AnyObject {
    var events: AsyncStream<WebRTCSignalingEvent> { get }

    func connect(_ request: WebRTCSignalingConnectRequest) async
    func disconnect() async
    func sendOffer(_ offer: WebRTCSessionDescription, to peerID: PeerID) async
    func sendAnswer(_ answer: WebRTCSessionDescription, to peerID: PeerID) async
    func sendCandidate(_ candidate: WebRTCIceCandidate, to peerID: PeerID) async
    func sendApplicationData(_ message: ApplicationDataMessage, to peerID: PeerID?) async
}

public final class CloudflareRealtimeSignalingClient: WebRTCSignalingClient {
    public var events: AsyncStream<WebRTCSignalingEvent> { eventSource.stream }
    private let eventSource = EventSource<WebRTCSignalingEvent>()

    public init() {}

    public func connect(_ request: WebRTCSignalingConnectRequest) async {
        eventSource.yield(.failed("Cloudflare Realtime signaling transport is intentionally injectable; provide a production WebSocket/HTTP implementation for the selected backend contract."))
    }

    public func disconnect() async {
        eventSource.yield(.disconnected)
    }

    public func sendOffer(_ offer: WebRTCSessionDescription, to peerID: PeerID) async {}
    public func sendAnswer(_ answer: WebRTCSessionDescription, to peerID: PeerID) async {}
    public func sendCandidate(_ candidate: WebRTCIceCandidate, to peerID: PeerID) async {}
    public func sendApplicationData(_ message: ApplicationDataMessage, to peerID: PeerID?) async {}
}
