import AVFoundation
import Codec
import CryptoKit
import Foundation
import OSLog
import RTC
import SessionManager
import VADGate

extension IntercomViewModel {
    func handleReceivedPacket(_ packet: ReceivedAudioPacket) {
        guard authenticatedPeerIDs.isEmpty || authenticatedPeerIDs.contains(packet.peerID) else {
            return
        }
        let receivedAt = packet.envelope.sentAt < 1_000_000
            ? packet.envelope.sentAt
            : Date().timeIntervalSince1970
        if let codec = packet.envelope.encodedVoice?.codec {
            setRemotePeerCodec(packet.peerID, codec: codec)
        }
        switch packet.packet {
        case .voice(_, let samples):
            jitterBuffer.enqueue(packet, receivedAt: receivedAt)
            receivedVoicePacketCount += 1
            lastReceivedAudioAt = receivedAt
            remoteVoiceReceivedAt[packet.peerID] = receivedAt
            refreshOtherAudioDuckingState(now: receivedAt)
            droppedAudioPacketCount = jitterBuffer.droppedFrameCount
            jitterQueuedFrameCount = jitterBuffer.queuedFrameCount
            applyReceivedVoiceMemberState(peerID: packet.peerID, voiceLevel: AudioLevelMeter.rmsLevel(samples: samples))
        case .keepalive:
            droppedAudioPacketCount = jitterBuffer.droppedFrameCount
            jitterQueuedFrameCount = jitterBuffer.queuedFrameCount
        }

        // In production, received packets can arrive in bursts on the main actor.
        // Draining here prevents playback from waiting for the next ticker cycle.
        if receivedAt >= 1_000_000 {
            drainJitterBuffer(now: receivedAt)
        }
    }

    func applyReceivedVoiceMemberState(peerID: String, voiceLevel: Float) {
        let clampedLevel = min(1, max(0, voiceLevel))
        let peakLevel = remoteVoicePeakWindows[peerID, default: VoicePeakWindow()].record(clampedLevel)
        withActiveGroup { group in
            guard let memberIndex = group.members.firstIndex(where: { $0.id == peerID }) else { return }
            group.members[memberIndex].isTalking = true
            group.members[memberIndex].voiceLevel = clampedLevel
            group.members[memberIndex].voicePeakLevel = peakLevel
            group.members[memberIndex].receivedAudioPacketCount += 1
            group.members[memberIndex].queuedAudioFrameCount += 1
        }
    }

    func removeDisconnectedAuthenticatedPeers(connectedPeerIDs: [String]) {
        let connectedPeerIDSet = Set(connectedPeerIDs)
        let disconnectedPeerIDs = authenticatedPeerIDs.filter { !connectedPeerIDSet.contains($0) }
        authenticatedPeerIDs.removeAll { !connectedPeerIDSet.contains($0) }

        for peerID in disconnectedPeerIDs {
            remoteVoiceReceivedAt.removeValue(forKey: peerID)
            setRemotePeer(peerID, isTalking: false)
        }
    }
}
