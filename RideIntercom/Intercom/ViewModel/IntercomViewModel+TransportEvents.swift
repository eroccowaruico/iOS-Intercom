import AVFoundation
import Codec
import CryptoKit
import Foundation
import OSLog
import RTC
import SessionManager
import VADGate

extension IntercomViewModel {
    func send(_ packet: OutboundAudioPacket) {
        switch packet {
        case .voice:
            sentVoicePacketCount += 1
            callSession.sendAudioFrame(packet)
        case .keepalive:
            callSession.sendControl(.keepalive)
        }
    }

    func broadcastControl(_ message: ControlMessage) {
        callSession.sendControl(message)
    }

    func broadcastMetadataKeepalive() {
        callSession.sendControl(.keepalive)
    }

    func sendStateMetadataSnapshot() {
        broadcastControl(.peerMuteState(isMuted: isMuted))
        broadcastMetadataKeepalive()
    }

    func handleTransportEvent(_ event: TransportEvent) {
        uiEventRevision += 1
        switch event {
        case .localNetworkStatus(let event):
            localNetworkStatus = event.status
            lastLocalNetworkPeerID = event.peerID
            lastLocalNetworkEventAt = event.occurredAt
        case .connected(let peerIDs):
            connectedPeerIDs = peerIDs
            addDiscoveredMembersIfNeeded(peerIDs: peerIDs)
            removeDisconnectedAuthenticatedPeers(connectedPeerIDs: peerIDs)
            localNetworkStatus = .connected
            if isLocalStandbyOnly {
                connectionState = .idle
            } else {
                connectionState = .localConnected
            }
            markConnectedMembers(peerIDs: peerIDs)
        case .authenticated(let peerIDs):
            let authenticatedPeerIDSet = Set(peerIDs)
            authenticatedPeerIDs = Array(authenticatedPeerIDSet).sorted()
            connectedPeerIDs = Array(Set(connectedPeerIDs).union(authenticatedPeerIDSet)).sorted()
            addDiscoveredMembersIfNeeded(peerIDs: authenticatedPeerIDs)
            if !isLocalStandbyOnly {
                connectionState = .localConnected
            }
            markConnectedMembers(peerIDs: connectedPeerIDs)
            startActiveCallAfterAuthenticatedPeer()
            sendStateMetadataSnapshot()
        case .remotePeerMuteState(let peerID, let isMuted):
            setRemotePeerMuteState(peerID: peerID, isMuted: isMuted)
        case .receivedApplicationData:
            break
        case .disconnected:
            stopAudioPipeline()
            connectedPeerIDs = []
            authenticatedPeerIDs = []
            localNetworkStatus = .idle
            connectionState = .idle
            isVoiceActive = false
            markMembers(.offline)
        case .linkFailed(let internetAvailable):
            _ = internetAvailable
            stopAudioPipeline()
            connectedPeerIDs = []
            authenticatedPeerIDs = []
            localNetworkStatus = .unavailable
            connectionState = .reconnectingOffline
            markMembers(.connecting)
        case .receivedPacket(let packet):
            handleReceivedPacket(packet)
        case .outboundPacketBuilt(let diagnostics):
            handleOutboundPacketDiagnostics(diagnostics)
        }
    }

    func handleOutboundPacketDiagnostics(_ diagnostics: OutboundPacketDiagnostics) {
        guard let rawMetadata = diagnostics.metadata else { return }
        let metadata = AudioTransmitMetadata(
            requestedCodec: preferredTransmitCodec,
            mediaCodec: rawMetadata.mediaCodec
        )
        setLocalActiveCodec(metadata.mediaCodec)

        transmitFallbackCount += 1
        let summary = "TX FB #\(transmitFallbackCount) / \(metadata.requestedCodec.rawValue)->\(metadata.mediaCodec.rawValue) "
        lastTransmitFallbackSummary = summary
        diagnosticsLogger.error("tx fallback route=\(diagnostics.route.rawValue, privacy: .public) stream=\(diagnostics.streamID.uuidString, privacy: .public) seq=\(diagnostics.sequenceNumber) req=\(metadata.requestedCodec.rawValue, privacy: .public) media=\(metadata.mediaCodec.rawValue, privacy: .public) ")
    }
}
