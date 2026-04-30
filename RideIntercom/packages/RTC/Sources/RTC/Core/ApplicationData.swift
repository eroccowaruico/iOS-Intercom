import Foundation

public enum ApplicationDataDelivery: String, Codable, Equatable, Sendable {
    case reliable
    case unreliable
}

public struct ApplicationDataMessage: Codable, Equatable, Sendable {
    public var namespace: String
    public var payload: Data
    public var delivery: ApplicationDataDelivery

    public init(namespace: String, payload: Data, delivery: ApplicationDataDelivery = .reliable) {
        self.namespace = namespace
        self.payload = payload
        self.delivery = delivery
    }
}

public struct ReceivedApplicationData: Equatable, Sendable {
    public var peerID: PeerID
    public var message: ApplicationDataMessage

    public init(peerID: PeerID, message: ApplicationDataMessage) {
        self.peerID = peerID
        self.message = message
    }
}
