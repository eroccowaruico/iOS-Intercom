import AVFoundation
import Codec
import CryptoKit
import Foundation
import Logging
import OSLog
import RTC
import SessionManager
import SoundIsolation
import VADGate

extension IntercomViewModel {
    var connectionLabel: String {
        if hasPresentedAuthenticatedConnection && !isAudioReady {
            return "\(connectionState.label) / Audio Idle"
        }
        return connectionState.label
    }

    var selectedGroupConnectionState: CallConnectionState {
        presentedConnectionState
    }

    var diagnosticsSnapshot: DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            audio: AudioDebugSnapshot(
                transmittedVoicePacketCount: sentVoicePacketCount,
                receivedVoicePacketCount: receivedVoicePacketCount,
                playedAudioFrameCount: playedAudioFrameCount
            ),
            playback: PlaybackDebugSnapshot(
                lastScheduledOutputRMS: lastScheduledOutputRMS,
                scheduledOutputBatchCount: scheduledOutputBatchCount,
                scheduledOutputFrameCount: scheduledOutputFrameCount
            ),
            connectedPeerCount: connectedPeerCount,
            authenticatedPeerCount: authenticatedPeerCount,
            localMemberID: localMemberIdentity.memberID,
            transportTypeName: callSession.activeRouteDebugTypeName,
            selectedGroupID: selectedGroup?.id,
            selectedGroupMemberCount: selectedGroup?.members.count ?? 0,
            groupHashPrefix: selectedGroup.map { String(credential(for: $0).groupHash.prefix(8)) },
            inviteStatusMessage: inviteStatusMessage,
            hasInviteURL: selectedGroupInviteURL != nil,
            localNetwork: LocalNetworkDebugSnapshot(
                status: localNetworkStatus,
                peerID: lastLocalNetworkPeerID,
                occurredAt: lastLocalNetworkEventAt
            ),
            reception: ReceptionDebugSnapshot(
                lastReceivedAudioAt: lastReceivedAudioAt,
                droppedAudioPacketCount: droppedAudioPacketCount,
                jitterQueuedFrameCount: jitterQueuedFrameCount
            )
        )
    }

    var callPresenceLabel: String {
        let connectionState = presentedConnectionState
        let localNetworkStatus = presentedLocalNetworkStatus
        if connectionState == .idle, localNetworkStatus != .idle {
            return "Waiting for Riders"
        }
        if hasPresentedAuthenticatedConnection && !isAudioReady {
            return "Connected / Audio Idle"
        }
        return connectionState.label
    }

    var canDisconnectCall: Bool {
        guard selectedGroup?.id == activeGroupID else { return false }
        return connectionState != .idle || isAudioReady || !authenticatedPeerIDs.isEmpty || localNetworkStatus != .idle
    }

    var routeLabel: String {
        if hasPresentedAuthenticatedConnection && !isAudioReady {
            switch presentedConnectionState {
            case .localConnected, .localConnecting:
                return "Local / Control Only"
            case .internetConnected, .internetConnecting:
                return "Internet / Control Only"
            case .idle, .reconnectingOffline:
                return "Offline"
            }
        }
        return switch presentedConnectionState {
        case .localConnected, .localConnecting:
            TransportRoute.local.rawValue
        case .internetConnected, .internetConnecting:
            TransportRoute.internet.rawValue
        case .idle, .reconnectingOffline:
            "Offline"
        }
    }

    var audioInputProcessingSummary: String {
        let isolationLabel: String
        if !supportsSoundIsolation {
            isolationLabel = "EFFECT UNAVAILABLE"
        } else {
            isolationLabel = isSoundIsolationEnabled ? "EFFECT ON" : "EFFECT OFF"
        }
        let duckingLabel = isOtherAudioDuckingActive ? "DUCK ACTIVE" : (isDuckOthersEnabled ? "DUCK READY" : "DUCK OFF")
        return "VAD \(vadSensitivity.label) / ISOLATION \(isolationLabel) / \(duckingLabel)"
    }

    var supportsSoundIsolation: Bool {
        VoiceIsolationSupport.isAvailable
    }

    var selectedTransmitCodec: AudioCodecIdentifier {
        AppAudioCodecBridge.resolvedPreferredCodec(preferredTransmitCodec, format: .intercomPacketAudio)
    }

    var codecDisplaySummary: String {
        if preferredTransmitCodec == selectedTransmitCodec {
            return "CODEC \(codecDisplayName(selectedTransmitCodec))"
        }
        return "CODEC \(codecDisplayName(preferredTransmitCodec)) -> \(codecDisplayName(selectedTransmitCodec))"
    }

    var codecFallbackSummary: String {
        if preferredTransmitCodec == selectedTransmitCodec {
            return "Fallback none"
        }
        return "Fallback: requested codec unavailable or route unsupported"
    }

    var codecBitRateSummary: String {
        if preferredTransmitCodec == .mpeg4AACELDv2 {
            return "\(aacELDv2BitRate / 1_000) kbps"
        }
        if preferredTransmitCodec == .opus {
            return "\(opusBitRate / 1_000) kbps"
        }
        return "linear PCM"
    }

    var vadAnalysisSummary: String {
        guard let latestVADAnalysis else {
            return "Analysis waiting"
        }
        return String(
            format: "%@ / NF %.1f dBFS / TH %.1f dBFS / G %.2f",
            latestVADAnalysis.state == .speech ? "Speech" : "Silence",
            latestVADAnalysis.noiseFloorDBFS,
            latestVADAnalysis.speechThresholdDBFS,
            latestVADAnalysis.gain
        )
    }

    var diagnosticsOverviewRows: [DiagnosticsOverviewRow] {
        [
            DiagnosticsOverviewRow(
                id: "call",
                title: "Call",
                icon: "checklist",
                summary: "CALL \(connectionLabel)",
                detail: "\(routeLabel) / \(isAudioReady ? "MEDIA ON" : "MEDIA IDLE")",
                severity: canDisconnectCall ? .ok : .neutral,
                accessibilityIdentifier: "realDeviceCallDebugSummaryLabel"
            ),
            DiagnosticsOverviewRow(
                id: "session",
                title: "Session",
                icon: "waveform",
                summary: sessionDiagnosticsSummary,
                detail: audioDeviceDiagnosticsSummary,
                severity: audioErrorMessage == nil ? .ok : .error,
                accessibilityIdentifier: "audioSessionSummaryLabel"
            ),
            DiagnosticsOverviewRow(
                id: "input",
                title: "Input Stream",
                icon: isMuted ? "mic.slash.fill" : "mic.fill",
                summary: inputStreamDiagnosticsSummary,
                detail: audioInputProcessingSummary,
                severity: isMuted ? .warning : (isAudioReady ? .ok : .neutral),
                accessibilityIdentifier: "audioInputProcessingSummaryLabel"
            ),
            DiagnosticsOverviewRow(
                id: "output",
                title: "Output Stream",
                icon: isOutputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                summary: outputStreamDiagnosticsSummary,
                detail: diagnosticsSnapshot.playback.summary,
                severity: isOutputMuted ? .warning : (isAudioReady ? .ok : .neutral),
                accessibilityIdentifier: "playbackDebugSummaryLabel"
            ),
            DiagnosticsOverviewRow(
                id: "codec",
                title: "Codec",
                icon: "cpu",
                summary: codecDisplaySummary,
                detail: "\(codecBitRateSummary) / \(codecFallbackSummary)",
                severity: preferredTransmitCodec == selectedTransmitCodec ? .ok : .warning,
                accessibilityIdentifier: "codecDebugSummaryLabel"
            ),
            DiagnosticsOverviewRow(
                id: "route",
                title: "Route Metrics",
                icon: "clock.arrow.circlepath",
                summary: routeMetricsDiagnosticsSummary,
                detail: diagnosticsSnapshot.localNetwork.summary(now: Date().timeIntervalSince1970),
                severity: routeMetricsSeverity,
                accessibilityIdentifier: "receptionDebugSummaryLabel"
            ),
            DiagnosticsOverviewRow(
                id: "mixer",
                title: "Mixer",
                icon: "waveform.path.ecg",
                summary: mixerDiagnosticsSummary,
                detail: "OUT \(Int(masterOutputVolume * 100))% / \(isOutputMuted ? "MUTED" : "LIVE")",
                severity: isOutputMuted || masterOutputVolume == 0 ? .warning : .ok,
                accessibilityIdentifier: "audioDebugSummaryLabel"
            ),
            DiagnosticsOverviewRow(
                id: "auth",
                title: "Authentication",
                icon: "checkmark.seal.fill",
                summary: diagnosticsSnapshot.authenticationSummary,
                detail: diagnosticsSnapshot.connectionSummary,
                severity: authenticatedPeerCount > 0 ? .ok : .neutral,
                accessibilityIdentifier: "authenticationDebugSummaryLabel"
            ),
            DiagnosticsOverviewRow(
                id: "invite",
                title: "Invite",
                icon: "square.and.arrow.up",
                summary: diagnosticsSnapshot.inviteSummary,
                detail: diagnosticsSnapshot.selectedGroupSummary,
                severity: selectedGroupInviteURL != nil ? .ok : .neutral,
                accessibilityIdentifier: "inviteDebugSummaryLabel"
            )
        ]
    }

    private var sessionDiagnosticsSummary: String {
        if audioSessionSnapshot.isActive {
            return "SESSION ACTIVE"
        }
        if lastAudioSessionConfigurationReport != nil {
            return "SESSION CONFIGURED"
        }
        return "SESSION IDLE"
    }

    private var audioDeviceDiagnosticsSummary: String {
        "IN \(selectedInputPort.name) / OUT \(selectedOutputPort.name)"
    }

    private var inputStreamDiagnosticsSummary: String {
        guard let snapshot = lastInputStreamOperationReport?.snapshot ?? lastVoiceProcessingOperationReport?.snapshot else {
            return isAudioReady ? "INPUT STARTING" : "INPUT IDLE"
        }
        return "\(snapshot.isRunning ? "INPUT RUN" : "INPUT IDLE") / \(streamFormatSummary(snapshot.format)) / FRM \(snapshot.processedFrameCount)"
    }

    private var outputStreamDiagnosticsSummary: String {
        guard let snapshot = lastOutputStreamOperationReport?.snapshot else {
            return isAudioReady ? "OUTPUT STARTING" : "OUTPUT IDLE"
        }
        return "\(snapshot.isRunning ? "OUTPUT RUN" : "OUTPUT IDLE") / \(streamFormatSummary(snapshot.format)) / FRM \(snapshot.processedFrameCount)"
    }

    private var routeMetricsDiagnosticsSummary: String {
        guard let lastRouteMetrics else {
            return diagnosticsSnapshot.reception.summary(now: Date().timeIntervalSince1970)
        }
        let rtt = lastRouteMetrics.rtt.map { String(format: "RTT %.0fms", $0 * 1_000) } ?? "RTT --"
        let jitter = lastRouteMetrics.jitter.map { String(format: "JIT %.0fms", $0 * 1_000) } ?? "JIT --"
        let loss = lastRouteMetrics.packetLoss.map { String(format: "LOSS %.1f%%", $0 * 100) } ?? "LOSS --"
        return "\(lastRouteMetrics.route.rawValue.uppercased()) / \(rtt) / \(jitter) / \(loss)"
    }

    private var routeMetricsSeverity: DiagnosticsSeverity {
        guard let lastRouteMetrics else { return .neutral }
        if lastRouteMetrics.droppedAudioFrameCount > 0 || (lastRouteMetrics.packetLoss ?? 0) > 0.05 {
            return .warning
        }
        return .ok
    }

    private var mixerDiagnosticsSummary: String {
        "MIX BUS \(max(1, authenticatedPeerCount)) / PLAY \(playedAudioFrameCount)"
    }

    private func streamFormatSummary(_ format: SessionManager.AudioStreamFormat) -> String {
        "\(Int(format.sampleRate / 1_000))k/\(format.channelCount)ch"
    }

    private func codecDisplayName(_ codec: AudioCodecIdentifier) -> String {
        if codec == .pcm16 { return "PCM 16" }
        if codec == .mpeg4AACELDv2 { return "AAC-ELD v2" }
        if codec == .opus { return "Opus" }
        return codec.rawValue
    }

    var connectedPeerCount: Int {
        connectedPeerIDs.count
    }

    var connectionDebugSummary: String {
        diagnosticsSnapshot.connectionSummary
    }

    var audioDebugSummary: String {
        diagnosticsSnapshot.audio.summary
    }

    var callSessionDebugTypeName: String {
        callSession.activeRouteDebugTypeName
    }

    var transportDebugSummary: String {
        diagnosticsSnapshot.transportSummary
    }

    var authenticatedPeerCount: Int {
        authenticatedPeerIDs.count
    }

    var authenticationDebugSummary: String {
        diagnosticsSnapshot.authenticationSummary
    }

    var localMemberDebugSummary: String {
        diagnosticsSnapshot.localMemberSummary
    }

    var selectedGroupDebugSummary: String {
        diagnosticsSnapshot.selectedGroupSummary
    }

    var groupHashDebugSummary: String {
        diagnosticsSnapshot.groupHashSummary
    }

    var inviteDebugSummary: String {
        diagnosticsSnapshot.inviteSummary
    }

    var localNetworkDebugSummary: String {
        diagnosticsSnapshot.localNetwork.summary(now: Date().timeIntervalSince1970)
    }

    var selectedGroupInviteURL: URL? {
        guard let selectedGroup else { return nil }
        let inviterMemberID: String
        if selectedGroup.members.contains(where: { $0.id == localMemberIdentity.memberID }) {
            inviterMemberID = localMemberIdentity.memberID
        } else if let firstMemberID = selectedGroup.members.first?.id {
            inviterMemberID = firstMemberID
        } else {
            return nil
        }

        let credential = credential(for: selectedGroup)
        let token = try? GroupInviteToken.make(
            groupID: selectedGroup.id,
            groupName: selectedGroup.name,
            groupSecret: credential.secret,
            inviterMemberID: inviterMemberID,
            expiresAt: Date().timeIntervalSince1970 + 7 * 24 * 60 * 60
        )
        return token.flatMap { try? GroupInviteTokenCodec.joinURL(for: $0) }
    }
}

struct DiagnosticsOverviewRow: Equatable, Identifiable {
    let id: String
    let title: String
    let icon: String
    let summary: String
    let detail: String
    let severity: DiagnosticsSeverity
    let accessibilityIdentifier: String
}

enum DiagnosticsSeverity: Equatable {
    case neutral
    case ok
    case warning
    case error
}
