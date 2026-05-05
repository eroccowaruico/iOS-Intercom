import AVFoundation
import Codec
import CryptoKit
import Foundation
import OSLog
import RTC
import SessionManager
import VADGate

extension IntercomViewModel {
    static func makeForCurrentProcess() -> IntercomViewModel {
        let localMemberIdentityStore = UserDefaultsLocalMemberIdentityStore()
        return IntercomViewModel(
            callSession: makeDefaultCallSession(localMemberIdentityStore: localMemberIdentityStore),
            credentialStore: KeychainGroupCredentialStore(),
            groupStore: UserDefaultsGroupStore(),
            localMemberIdentityStore: localMemberIdentityStore,
            audioFramePlayer: makeDefaultAudioFramePlayer()
        )
    }

    static func makeDefaultCallSession(localMemberIdentityStore: any LocalMemberIdentityStoring) -> CallSession {
        RideIntercomCallSessionAdapter(memberID: localMemberIdentityStore.loadOrCreate().memberID)
    }

    static func makeDefaultAudioFramePlayer() -> AudioFramePlaying {
        BufferedAudioFramePlayer(renderer: SystemAudioOutputRenderer())
    }
}
