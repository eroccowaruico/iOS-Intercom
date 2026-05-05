import Foundation
import Logging
import RTC

extension IntercomViewModel {
    func handleReceivedAudioFrame(_ received: RTC.ReceivedAudioFrame) {
        let peerID = received.peerID.rawValue
        guard authenticatedPeerIDs.isEmpty || authenticatedPeerIDs.contains(peerID) else {
            return
        }

        let frame = received.frame
        let receivedAt = frame.capturedAt < 1_000_000
            ? Date().timeIntervalSince1970
            : frame.capturedAt
        receivedVoicePacketCount += 1
        lastReceivedAudioAt = receivedAt
        remoteVoiceReceivedAt[peerID] = receivedAt
        applyReceivedVoiceMemberState(peerID: peerID, voiceLevel: AudioLevelMeter.rmsLevel(samples: frame.samples))
        scheduleOutputFrame(peerID: peerID, frame: frame, receivedAt: receivedAt)
        refreshOtherAudioDuckingState(now: receivedAt)
    }

    func handleRouteMetrics(_ metrics: RTC.RouteMetrics) {
        lastRouteMetrics = metrics
        droppedAudioPacketCount = metrics.droppedAudioFrameCount
        jitterQueuedFrameCount = metrics.queuedAudioFrameCount
        receivedVoicePacketCount = max(receivedVoicePacketCount, metrics.receivedAudioFrameCount)
        if metrics.droppedAudioFrameCount > 0 || (metrics.packetLoss ?? 0) > 0.05 {
            AppLoggers.rtc.warning(
                "rtc.route.degraded",
                metadata: .event("rtc.route.degraded", [
                    "route": "\(metrics.route.rawValue)",
                    "packetLoss": "\(metrics.packetLoss ?? 0)",
                    "drop": "\(metrics.droppedAudioFrameCount)"
                ])
            )
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
