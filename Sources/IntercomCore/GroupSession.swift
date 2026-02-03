import Foundation

public struct GroupSession: Sendable, Equatable {
    public let groupID: UUID
    public let groupHash: String
    public let displayName: String

    public init(groupID: UUID, groupHash: String, displayName: String) {
        self.groupID = groupID
        self.groupHash = groupHash
        self.displayName = displayName
    }
}
