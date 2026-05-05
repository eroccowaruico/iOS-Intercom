import AVFoundation
import Codec
import CryptoKit
import Foundation
import OSLog
import RTC
import SessionManager
import VADGate

extension IntercomGroup {
    func withMemberAuthenticationState(_ state: PeerAuthenticationState) -> IntercomGroup {
        var updated = self
        updated.members = members.map { member in
            var updatedMember = member
            updatedMember.authenticationState = state
            return updatedMember
        }
        return updated
    }
}
