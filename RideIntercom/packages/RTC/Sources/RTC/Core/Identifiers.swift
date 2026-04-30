import CryptoKit
import Foundation

public struct PeerID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public struct PeerDescriptor: Hashable, Codable, Sendable {
    public var id: PeerID
    public var displayName: String

    public init(id: PeerID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct RTCCredential: Equatable, Sendable {
    public var groupHash: String
    public var sharedSecret: Data

    public init(groupHash: String, sharedSecret: Data) {
        self.groupHash = groupHash
        self.sharedSecret = sharedSecret
    }

    public static func derived(groupID: String, secret: String) -> RTCCredential {
        var hashInput = Data(groupID.utf8)
        hashInput.append(0)
        hashInput.append(contentsOf: secret.utf8)

        var keyInput = Data("ride-intercom-rtc-v2".utf8)
        keyInput.append(0)
        keyInput.append(contentsOf: groupID.utf8)
        keyInput.append(0)
        keyInput.append(contentsOf: secret.utf8)

        return RTCCredential(
            groupHash: SHA256.hash(data: hashInput).hexString,
            sharedSecret: Data(SHA256.hash(data: keyInput))
        )
    }
}

extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
