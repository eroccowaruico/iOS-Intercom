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
