import Foundation

public struct AudioFrame: Sendable, Equatable, Codable {
    public let streamID: UUID
    public let sequenceNumber: UInt64
    public let timestamp: TimeInterval
    public let payload: Data
    public let isKeepAlive: Bool

    public init(streamID: UUID, sequenceNumber: UInt64, timestamp: TimeInterval, payload: Data, isKeepAlive: Bool) {
        self.streamID = streamID
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.payload = payload
        self.isKeepAlive = isKeepAlive
    }
}
