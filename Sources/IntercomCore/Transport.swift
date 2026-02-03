import Foundation

public enum TransportEvent: Sendable, Equatable {
    case peerJoined(peerID: String)
    case peerLeft(peerID: String)
    case linkMetrics(LinkMetrics)
    case didDisconnect(reason: String)
}

public struct LinkMetrics: Sendable, Equatable, Codable {
    public let rttMilliseconds: Double
    public let packetLossRate: Double
    public let jitterMilliseconds: Double
    public let peerCount: Int

    public init(rttMilliseconds: Double, packetLossRate: Double, jitterMilliseconds: Double, peerCount: Int) {
        self.rttMilliseconds = rttMilliseconds
        self.packetLossRate = packetLossRate
        self.jitterMilliseconds = jitterMilliseconds
        self.peerCount = peerCount
    }
}

public protocol Transport: AnyObject {
    var onEvent: (@Sendable (TransportEvent) -> Void)? { get set }

    func connect(group: GroupSession) async throws
    func disconnect()
    func sendAudioFrame(_ frame: AudioFrame) throws
    func sendControl(_ message: ControlMessage) throws
}
