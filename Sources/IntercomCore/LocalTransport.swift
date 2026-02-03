import Foundation
import MultipeerConnectivity

public final class LocalTransport: NSObject, Transport {
    public var onEvent: (@Sendable (TransportEvent) -> Void)?

    private let serviceType: String
    private let myPeerID: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private var activeGroupHash: String?

    public init(displayName: String, serviceType: String = "intercom") {
        self.serviceType = serviceType
        self.myPeerID = MCPeerID(displayName: displayName)
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        self.advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        self.browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    public func connect(group: GroupSession) async throws {
        activeGroupHash = group.groupHash
        advertiser.stopAdvertisingPeer()
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["groupHash": group.groupHash],
            serviceType: serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    public func disconnect() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        activeGroupHash = nil
    }

    public func sendAudioFrame(_ frame: AudioFrame) throws {
        let payload = try JSONEncoder().encode(frame)
        try sendData(payload, mode: .unreliable)
    }

    public func sendControl(_ message: ControlMessage) throws {
        let payload = try JSONEncoder().encode(message)
        try sendData(payload, mode: .reliable)
    }

    private func sendData(_ data: Data, mode: MCSessionSendDataMode) throws {
        let connectedPeers = session.connectedPeers
        guard !connectedPeers.isEmpty else { return }
        try session.send(data, toPeers: connectedPeers, with: mode)
    }
}

extension LocalTransport: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            onEvent?(.peerJoined(peerID: peerID.displayName))
        case .notConnected:
            onEvent?(.peerLeft(peerID: peerID.displayName))
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Decode on higher-level components.
    }

    public func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {
    }

    public func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
    }

    public func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
    }
}

extension LocalTransport: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
    }
}

extension LocalTransport: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let groupHash = activeGroupHash else { return }
        guard info?["groupHash"] == groupHash else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    }
}
