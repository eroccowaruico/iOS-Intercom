import Foundation

enum InviteService {
    static func makeInviteURL(
        group: IntercomGroup,
        inviterMemberID: String,
        credential: GroupAccessCredential,
        now: TimeInterval = Date().timeIntervalSince1970,
        expiresIn: TimeInterval = 7 * 24 * 60 * 60
    ) -> URL? {
        let token = try? GroupInviteToken.make(
            groupID: group.id,
            groupName: group.name,
            groupSecret: credential.secret,
            inviterMemberID: inviterMemberID,
            expiresAt: now + expiresIn
        )
        return token.flatMap { try? GroupInviteTokenCodec.joinURL(for: $0) }
    }
}

struct AcceptInviteUseCaseResult {
    let groups: [IntercomGroup]
    let selectedGroup: IntercomGroup
    let inviteStatusMessage: String
}

enum AcceptInviteUseCase {
    static func execute(
        url: URL,
        now: TimeInterval,
        localMemberIdentity: LocalMemberIdentity,
        groups: [IntercomGroup],
        credentialStore: GroupCredentialStoring
    ) throws -> AcceptInviteUseCaseResult {
        let token = try GroupInviteTokenCodec.decodeJoinURL(url)
        guard !token.isExpired(now: now) else {
            throw GroupInviteTokenError.expired
        }

        credentialStore.save(GroupAccessCredential(groupID: token.groupID, secret: token.groupSecret))

        let group = try IntercomGroup(
            id: token.groupID,
            name: token.groupName,
            members: [
                GroupMember(id: localMemberIdentity.memberID, displayName: localMemberIdentity.displayName),
                GroupMember(id: token.inviterMemberID, displayName: "Inviter")
            ]
        )

        var updatedGroups = groups
        if let existingIndex = updatedGroups.firstIndex(where: { $0.id == group.id }) {
            updatedGroups[existingIndex] = group
        } else {
            updatedGroups.insert(group, at: 0)
        }

        return AcceptInviteUseCaseResult(
            groups: updatedGroups,
            selectedGroup: group,
            inviteStatusMessage: "JOINED \(token.groupName)"
        )
    }
}