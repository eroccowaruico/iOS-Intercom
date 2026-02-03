import Foundation

public enum ControlMessage: Sendable, Equatable, Codable {
    case handshake(groupHash: String, memberID: String)
    case keepAlive
    case metricsRequest
    case metricsResponse(LinkMetrics)

    private enum CodingKeys: String, CodingKey {
        case type
        case groupHash
        case memberID
        case metrics
    }

    private enum MessageType: String, Codable {
        case handshake
        case keepAlive
        case metricsRequest
        case metricsResponse
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        switch type {
        case .handshake:
            let groupHash = try container.decode(String.self, forKey: .groupHash)
            let memberID = try container.decode(String.self, forKey: .memberID)
            self = .handshake(groupHash: groupHash, memberID: memberID)
        case .keepAlive:
            self = .keepAlive
        case .metricsRequest:
            self = .metricsRequest
        case .metricsResponse:
            let metrics = try container.decode(LinkMetrics.self, forKey: .metrics)
            self = .metricsResponse(metrics)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .handshake(groupHash, memberID):
            try container.encode(MessageType.handshake, forKey: .type)
            try container.encode(groupHash, forKey: .groupHash)
            try container.encode(memberID, forKey: .memberID)
        case .keepAlive:
            try container.encode(MessageType.keepAlive, forKey: .type)
        case .metricsRequest:
            try container.encode(MessageType.metricsRequest, forKey: .type)
        case let .metricsResponse(metrics):
            try container.encode(MessageType.metricsResponse, forKey: .type)
            try container.encode(metrics, forKey: .metrics)
        }
    }
}
